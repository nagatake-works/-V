#!/usr/bin/env python3
"""
VTuber Chat - 統合サーバー
- SQLite DB (ユーザー/モデル共有/ランキング)
- OpenAI API プロキシ
- AivisCloud TTS + edge-tts フォールバック
- 画像/Live2D ZIPアップロード
"""
import http.server
import socketserver
import json
import urllib.request
import urllib.error
import os
import asyncio
import io
import sqlite3
import time
import re
import base64
import hashlib
import threading
from datetime import datetime, timezone
from urllib.parse import urlparse, parse_qs

PORT = 5060
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(BASE_DIR, "build/web")
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
DB_PATH = os.path.join(BASE_DIR, "vtchat.db")

# ── アップロードディレクトリ作成 ──
os.makedirs(os.path.join(UPLOAD_DIR, "models"), exist_ok=True)
os.makedirs(os.path.join(UPLOAD_DIR, "users"), exist_ok=True)

# ══════════════════════════════════════════════════════════
#  環境変数
# ══════════════════════════════════════════════════════════
def _load_env_file():
    env_path = os.path.join(BASE_DIR, '.env')
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    os.environ[k.strip()] = v.strip()
_load_env_file()

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
AIVIS_API_KEY  = os.environ.get("AIVIS_API_KEY", "")
AIVIS_MODEL_UUID = "a670e6b8-0852-45b2-8704-1bc9862f2fe6"
AIVIS_API_URL    = "https://api.aivis-project.com/v1/tts/synthesize"
AIVIS_TIMEOUT    = 5
EDGE_TTS_VOICE   = "ja-JP-NanamiNeural"

# ══════════════════════════════════════════════════════════
#  SQLite Database
# ══════════════════════════════════════════════════════════
_db_lock = threading.Lock()

def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn

def init_db():
    conn = get_db()
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS users (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL DEFAULT 'ゲスト',
        icon_path   TEXT DEFAULT NULL,
        profile     TEXT DEFAULT '',
        created_at  TEXT DEFAULT (datetime('now')),
        updated_at  TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS models (
        id              TEXT PRIMARY KEY,
        owner_id        TEXT NOT NULL,
        name            TEXT NOT NULL,
        creator_name    TEXT DEFAULT 'ユーザー',
        personality     TEXT DEFAULT '',
        greeting        TEXT DEFAULT 'はじめまして！よろしくね！',
        voice_id        TEXT DEFAULT '',
        thumbnail_path  TEXT DEFAULT NULL,
        sd_image_path   TEXT DEFAULT NULL,
        has_live2d      INTEGER DEFAULT 0,
        l2d_zip_path    TEXT DEFAULT NULL,
        display_scale   REAL DEFAULT 1.0,
        display_offset_y REAL DEFAULT 0.0,
        total_chats     INTEGER DEFAULT 0,
        created_at      TEXT DEFAULT (datetime('now')),
        updated_at      TEXT DEFAULT (datetime('now')),
        FOREIGN KEY (owner_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS chat_logs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id     TEXT NOT NULL,
        model_id    TEXT NOT NULL,
        points      INTEGER DEFAULT 10,
        month_key   TEXT NOT NULL,
        created_at  TEXT DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_chat_logs_month ON chat_logs(month_key, model_id);
    CREATE INDEX IF NOT EXISTS idx_chat_logs_user ON chat_logs(user_id, month_key);
    CREATE INDEX IF NOT EXISTS idx_models_chats ON models(total_chats DESC);
    CREATE INDEX IF NOT EXISTS idx_models_owner ON models(owner_id);
    """)
    # システムユーザーを挿入（公式モデル用）
    if not conn.execute("SELECT id FROM users WHERE id='__system__'").fetchone():
        conn.execute("INSERT INTO users (id, name, profile) VALUES ('__system__','SYSTEM','公式アカウント')")
    # デフォルトモデル「来鳥アルエ」を挿入（存在しなければ）
    existing = conn.execute("SELECT id FROM models WHERE id='arue_default'").fetchone()
    if not existing:
        conn.execute("""INSERT INTO models (id, owner_id, name, creator_name, personality, greeting, voice_id,
            thumbnail_path, sd_image_path, has_live2d, display_scale, display_offset_y, total_chats)
            VALUES ('arue_default','__system__','来鳥アルエ','公式',
            '20歳の天使系VTuber。優しくて好奇心旺盛。語尾に「〜だよ」「〜なの」をつける。',
            'はじめまして！来鳥アルエだよ♪ よろしくね！','',
            'img/arue_chibi.png','img/arue_chibi.png',1,1.0,0.0,0)""")
    conn.commit()
    conn.close()
    print(f"[DB] Initialized: {DB_PATH}")

init_db()

# ══════════════════════════════════════════════════════════
#  Helpers
# ══════════════════════════════════════════════════════════
def _json_resp(handler, code, data):
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)

def _read_body(handler):
    length = int(handler.headers.get("Content-Length", 0))
    return handler.rfile.read(length)

def _read_json(handler):
    return json.loads(_read_body(handler))

def _now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def _month_key():
    return datetime.now(timezone.utc).strftime("%Y-%m")

def _save_upload(data_bytes, dest_path):
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    with open(dest_path, "wb") as f:
        f.write(data_bytes)
    return dest_path

def _parse_multipart(handler):
    """Simple multipart/form-data parser. Returns dict of {field: bytes}"""
    content_type = handler.headers.get("Content-Type", "")
    if "boundary=" not in content_type:
        return {}
    boundary = content_type.split("boundary=")[1].strip()
    if boundary.startswith('"') and boundary.endswith('"'):
        boundary = boundary[1:-1]
    body = _read_body(handler)
    parts = body.split(("--" + boundary).encode())
    result = {}
    for part in parts:
        if b"Content-Disposition" not in part:
            continue
        header_end = part.find(b"\r\n\r\n")
        if header_end < 0:
            continue
        headers_raw = part[:header_end].decode("utf-8", errors="replace")
        data = part[header_end+4:]
        if data.endswith(b"\r\n"):
            data = data[:-2]
        name_match = re.search(r'name="([^"]+)"', headers_raw)
        if name_match:
            result[name_match.group(1)] = data
    return result

def _edge_tts_synthesize(text):
    import edge_tts
    async def _synth():
        comm = edge_tts.Communicate(text, voice=EDGE_TTS_VOICE)
        buf = io.BytesIO()
        async for chunk in comm.stream():
            if chunk["type"] == "audio":
                buf.write(chunk["data"])
        return buf.getvalue()
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(_synth())
    finally:
        loop.close()

# ══════════════════════════════════════════════════════════
#  HTTP Handler
# ══════════════════════════════════════════════════════════
class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-User-Id")
        self.send_header("X-Frame-Options", "ALLOWALL")
        self.send_header("Content-Security-Policy", "frame-ancestors *")

    def end_headers(self):
        self._send_cors_headers()
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.send_header("Content-Length", "0")
        super().end_headers()

    # ── ルーティング ──
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == "/api/models":
            return self._api_get_models(qs)
        if path.startswith("/api/models/") and path.count("/") == 3:
            model_id = path.split("/")[3]
            return self._api_get_model(model_id)
        if path.startswith("/api/user/") and path.count("/") == 3:
            user_id = path.split("/")[3]
            return self._api_get_user(user_id)
        if path.startswith("/api/ranking/"):
            parts = path.split("/")
            model_id = parts[3] if len(parts) > 3 else ""
            return self._api_get_ranking(model_id, qs)
        if path.startswith("/uploads/"):
            # 静的ファイルとしてアップロード画像を配信
            file_path = os.path.join(BASE_DIR, path.lstrip("/"))
            if os.path.isfile(file_path):
                self.send_response(200)
                ext = os.path.splitext(file_path)[1].lower()
                ct_map = {".webp":"image/webp",".png":"image/png",".jpg":"image/jpeg",".jpeg":"image/jpeg",".gif":"image/gif",".zip":"application/zip"}
                self.send_header("Content-Type", ct_map.get(ext, "application/octet-stream"))
                self.send_header("Content-Length", str(os.path.getsize(file_path)))
                self.send_header("Cache-Control", "public, max-age=86400")
                self.end_headers()
                with open(file_path, "rb") as f:
                    self.wfile.write(f.read())
                return
            self.send_response(404)
            self.end_headers()
            return
        # 通常の静的ファイル配信
        super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/chat":
            return self._handle_chat_proxy()
        if path == "/api/tts":
            return self._handle_tts_proxy()
        if path == "/api/user/register":
            return self._api_register_user()
        if path == "/api/models":
            return self._api_create_model()
        if path == "/api/chat-log":
            return self._api_chat_log()
        # 画像アップロード: /api/models/{id}/thumbnail, /api/models/{id}/sd-image, /api/models/{id}/l2d-zip
        if path.startswith("/api/models/") and path.count("/") == 4:
            parts = path.split("/")
            model_id, action = parts[3], parts[4]
            if action == "thumbnail":
                return self._api_upload_model_image(model_id, "thumbnail")
            elif action == "sd-image":
                return self._api_upload_model_image(model_id, "sd_image")
            elif action == "l2d-zip":
                return self._api_upload_l2d_zip(model_id)
        if path.startswith("/api/user/") and path.endswith("/icon"):
            user_id = path.split("/")[3]
            return self._api_upload_user_icon(user_id)
        self.send_response(404)
        self.end_headers()

    def do_PUT(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path.startswith("/api/models/") and path.count("/") == 3:
            model_id = path.split("/")[3]
            return self._api_update_model(model_id)
        if path.startswith("/api/user/") and path.count("/") == 3:
            user_id = path.split("/")[3]
            return self._api_update_user(user_id)
        self.send_response(404)
        self.end_headers()

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path.startswith("/api/models/") and path.count("/") == 3:
            model_id = path.split("/")[3]
            return self._api_delete_model(model_id)
        self.send_response(404)
        self.end_headers()

    # ══════════════════════════════════════════════
    #  User API
    # ══════════════════════════════════════════════
    def _api_register_user(self):
        data = _read_json(self)
        uid = data.get("id", "").strip()
        name = data.get("name", "ゲスト").strip() or "ゲスト"
        if not uid:
            return _json_resp(self, 400, {"error": "id required"})
        with _db_lock:
            conn = get_db()
            existing = conn.execute("SELECT id, name, icon_path, profile FROM users WHERE id=?", (uid,)).fetchone()
            if existing:
                conn.close()
                return _json_resp(self, 200, dict(existing))
            conn.execute("INSERT INTO users (id, name) VALUES (?, ?)", (uid, name))
            conn.commit()
            user = conn.execute("SELECT id, name, icon_path, profile FROM users WHERE id=?", (uid,)).fetchone()
            conn.close()
        print(f"[USER] Registered: {uid} ({name})")
        return _json_resp(self, 201, dict(user))

    def _api_get_user(self, user_id):
        conn = get_db()
        user = conn.execute("SELECT id, name, icon_path, profile, created_at FROM users WHERE id=?", (user_id,)).fetchone()
        conn.close()
        if not user:
            return _json_resp(self, 404, {"error": "User not found"})
        return _json_resp(self, 200, dict(user))

    def _api_update_user(self, user_id):
        caller = self.headers.get("X-User-Id", "")
        if caller != user_id:
            return _json_resp(self, 403, {"error": "Forbidden"})
        data = _read_json(self)
        with _db_lock:
            conn = get_db()
            user = conn.execute("SELECT id FROM users WHERE id=?", (user_id,)).fetchone()
            if not user:
                conn.close()
                return _json_resp(self, 404, {"error": "User not found"})
            fields, vals = [], []
            for key in ("name", "profile"):
                if key in data:
                    fields.append(f"{key}=?")
                    vals.append(data[key])
            if fields:
                fields.append("updated_at=?")
                vals.append(_now_iso())
                vals.append(user_id)
                conn.execute(f"UPDATE users SET {','.join(fields)} WHERE id=?", vals)
                conn.commit()
            updated = conn.execute("SELECT id, name, icon_path, profile FROM users WHERE id=?", (user_id,)).fetchone()
            conn.close()
        return _json_resp(self, 200, dict(updated))

    def _api_upload_user_icon(self, user_id):
        caller = self.headers.get("X-User-Id", "")
        if caller != user_id:
            return _json_resp(self, 403, {"error": "Forbidden"})
        parts = _parse_multipart(self)
        file_data = parts.get("file") or parts.get("icon")
        if not file_data:
            return _json_resp(self, 400, {"error": "No file"})
        dest = os.path.join(UPLOAD_DIR, "users", user_id, "icon.webp")
        _save_upload(file_data, dest)
        rel_path = f"/uploads/users/{user_id}/icon.webp"
        with _db_lock:
            conn = get_db()
            conn.execute("UPDATE users SET icon_path=?, updated_at=? WHERE id=?", (rel_path, _now_iso(), user_id))
            conn.commit()
            conn.close()
        return _json_resp(self, 200, {"icon_path": rel_path})

    # ══════════════════════════════════════════════
    #  Model API
    # ══════════════════════════════════════════════
    def _api_get_models(self, qs):
        conn = get_db()
        sort = qs.get("sort", ["recent"])[0]
        q = qs.get("q", [""])[0].strip()
        order = "total_chats DESC" if sort == "popular" else "created_at DESC"
        if q:
            rows = conn.execute(f"SELECT * FROM models WHERE name LIKE ? ORDER BY {order}", (f"%{q}%",)).fetchall()
        else:
            rows = conn.execute(f"SELECT * FROM models ORDER BY {order}").fetchall()
        result = []
        for r in rows:
            d = dict(r)
            # オーナー名を付与
            owner = conn.execute("SELECT name, icon_path FROM users WHERE id=?", (d["owner_id"],)).fetchone()
            d["owner_name"] = owner["name"] if owner else "不明"
            d["owner_icon"] = owner["icon_path"] if owner else None
            result.append(d)
        conn.close()
        return _json_resp(self, 200, result)

    def _api_get_model(self, model_id):
        conn = get_db()
        row = conn.execute("SELECT * FROM models WHERE id=?", (model_id,)).fetchone()
        if not row:
            conn.close()
            return _json_resp(self, 404, {"error": "Model not found"})
        d = dict(row)
        owner = conn.execute("SELECT name, icon_path FROM users WHERE id=?", (d["owner_id"],)).fetchone()
        d["owner_name"] = owner["name"] if owner else "不明"
        d["owner_icon"] = owner["icon_path"] if owner else None
        conn.close()
        return _json_resp(self, 200, d)

    def _api_create_model(self):
        data = _read_json(self)
        owner_id = data.get("owner_id", "").strip()
        if not owner_id:
            return _json_resp(self, 400, {"error": "owner_id required"})
        with _db_lock:
            conn = get_db()
            # 1人1モデル制限チェック
            count = conn.execute("SELECT COUNT(*) as c FROM models WHERE owner_id=?", (owner_id,)).fetchone()["c"]
            if count >= 1:
                conn.close()
                return _json_resp(self, 409, {"error": "1人1モデルまでです", "code": "MODEL_LIMIT"})
            model_id = data.get("id") or f"user_{int(time.time())}_{hashlib.md5(owner_id.encode()).hexdigest()[:6]}"
            conn.execute("""INSERT INTO models (id, owner_id, name, creator_name, personality, greeting, voice_id,
                has_live2d, display_scale, display_offset_y)
                VALUES (?,?,?,?,?,?,?,?,?,?)""", (
                model_id, owner_id,
                data.get("name", "名前未設定").strip(),
                data.get("creator_name", "ユーザー"),
                data.get("personality", ""),
                data.get("greeting", "はじめまして！よろしくね！"),
                data.get("voice_id", ""),
                1 if data.get("has_live2d") else 0,
                float(data.get("display_scale", 1.0)),
                float(data.get("display_offset_y", 0.0)),
            ))
            conn.commit()
            row = conn.execute("SELECT * FROM models WHERE id=?", (model_id,)).fetchone()
            conn.close()
        print(f"[MODEL] Created: {model_id} by {owner_id}")
        return _json_resp(self, 201, dict(row))

    def _api_update_model(self, model_id):
        caller = self.headers.get("X-User-Id", "")
        data = _read_json(self)
        with _db_lock:
            conn = get_db()
            row = conn.execute("SELECT owner_id FROM models WHERE id=?", (model_id,)).fetchone()
            if not row:
                conn.close()
                return _json_resp(self, 404, {"error": "Model not found"})
            if row["owner_id"] != caller and row["owner_id"] != "__system__":
                conn.close()
                return _json_resp(self, 403, {"error": "自分のモデルのみ編集可能です"})
            if row["owner_id"] == "__system__":
                conn.close()
                return _json_resp(self, 403, {"error": "公式モデルは編集できません"})
            allowed = ("name","personality","greeting","voice_id","display_scale","display_offset_y","creator_name")
            fields, vals = [], []
            for k in allowed:
                if k in data:
                    fields.append(f"{k}=?")
                    vals.append(data[k])
            if fields:
                fields.append("updated_at=?")
                vals.append(_now_iso())
                vals.append(model_id)
                conn.execute(f"UPDATE models SET {','.join(fields)} WHERE id=?", vals)
                conn.commit()
            updated = conn.execute("SELECT * FROM models WHERE id=?", (model_id,)).fetchone()
            conn.close()
        return _json_resp(self, 200, dict(updated))

    def _api_delete_model(self, model_id):
        caller = self.headers.get("X-User-Id", "")
        with _db_lock:
            conn = get_db()
            row = conn.execute("SELECT owner_id FROM models WHERE id=?", (model_id,)).fetchone()
            if not row:
                conn.close()
                return _json_resp(self, 404, {"error": "Model not found"})
            if row["owner_id"] == "__system__":
                conn.close()
                return _json_resp(self, 403, {"error": "公式モデルは削除できません"})
            if row["owner_id"] != caller:
                conn.close()
                return _json_resp(self, 403, {"error": "自分のモデルのみ削除可能です"})
            conn.execute("DELETE FROM models WHERE id=?", (model_id,))
            conn.execute("DELETE FROM chat_logs WHERE model_id=?", (model_id,))
            conn.commit()
            conn.close()
        # ファイル削除
        import shutil
        model_dir = os.path.join(UPLOAD_DIR, "models", model_id)
        if os.path.isdir(model_dir):
            shutil.rmtree(model_dir, ignore_errors=True)
        print(f"[MODEL] Deleted: {model_id} by {caller}")
        return _json_resp(self, 200, {"deleted": model_id})

    def _api_upload_model_image(self, model_id, img_type):
        caller = self.headers.get("X-User-Id", "")
        parts = _parse_multipart(self)
        file_data = parts.get("file") or parts.get("image")
        if not file_data:
            return _json_resp(self, 400, {"error": "No file"})
        with _db_lock:
            conn = get_db()
            row = conn.execute("SELECT owner_id FROM models WHERE id=?", (model_id,)).fetchone()
            if not row:
                conn.close()
                return _json_resp(self, 404, {"error": "Model not found"})
            if row["owner_id"] != caller and row["owner_id"] != "__system__":
                conn.close()
                return _json_resp(self, 403, {"error": "Forbidden"})
            ext = "webp"
            filename = f"{img_type}.{ext}"
            dest = os.path.join(UPLOAD_DIR, "models", model_id, filename)
            _save_upload(file_data, dest)
            rel_path = f"/uploads/models/{model_id}/{filename}"
            col = "thumbnail_path" if img_type == "thumbnail" else "sd_image_path"
            conn.execute(f"UPDATE models SET {col}=?, updated_at=? WHERE id=?", (rel_path, _now_iso(), model_id))
            conn.commit()
            conn.close()
        return _json_resp(self, 200, {"path": rel_path})

    def _api_upload_l2d_zip(self, model_id):
        caller = self.headers.get("X-User-Id", "")
        parts = _parse_multipart(self)
        file_data = parts.get("file") or parts.get("zip")
        if not file_data:
            return _json_resp(self, 400, {"error": "No file"})
        with _db_lock:
            conn = get_db()
            row = conn.execute("SELECT owner_id FROM models WHERE id=?", (model_id,)).fetchone()
            if not row:
                conn.close()
                return _json_resp(self, 404, {"error": "Model not found"})
            if row["owner_id"] != caller:
                conn.close()
                return _json_resp(self, 403, {"error": "Forbidden"})
            dest = os.path.join(UPLOAD_DIR, "models", model_id, "l2d.zip")
            _save_upload(file_data, dest)
            rel_path = f"/uploads/models/{model_id}/l2d.zip"
            conn.execute("UPDATE models SET l2d_zip_path=?, has_live2d=1, updated_at=? WHERE id=?",
                        (rel_path, _now_iso(), model_id))
            conn.commit()
            conn.close()
        print(f"[MODEL] L2D ZIP uploaded: {model_id} ({len(file_data)} bytes)")
        return _json_resp(self, 200, {"path": rel_path})

    # ══════════════════════════════════════════════
    #  Chat Log / Ranking API
    # ══════════════════════════════════════════════
    def _api_chat_log(self):
        data = _read_json(self)
        user_id = data.get("user_id", "").strip()
        model_id = data.get("model_id", "").strip()
        if not user_id or not model_id:
            return _json_resp(self, 400, {"error": "user_id and model_id required"})
        mk = _month_key()
        with _db_lock:
            conn = get_db()
            conn.execute("INSERT INTO chat_logs (user_id, model_id, points, month_key) VALUES (?,?,10,?)",
                        (user_id, model_id, mk))
            conn.execute("UPDATE models SET total_chats = total_chats + 1 WHERE id=?", (model_id,))
            conn.commit()
            conn.close()
        return _json_resp(self, 200, {"ok": True, "points": 10, "month_key": mk})

    def _api_get_ranking(self, model_id, qs):
        month = qs.get("month", [_month_key()])[0]
        conn = get_db()
        rows = conn.execute("""
            SELECT cl.user_id, u.name, u.icon_path, SUM(cl.points) as total_points
            FROM chat_logs cl
            LEFT JOIN users u ON cl.user_id = u.id
            WHERE cl.model_id = ? AND cl.month_key = ?
            GROUP BY cl.user_id
            ORDER BY total_points DESC
            LIMIT 50
        """, (model_id, month)).fetchall()
        result = []
        for i, r in enumerate(rows):
            result.append({
                "rank": i + 1,
                "user_id": r["user_id"],
                "name": r["name"] or "ゲスト",
                "icon_path": r["icon_path"],
                "total_points": r["total_points"],
            })
        conn.close()
        return _json_resp(self, 200, {"model_id": model_id, "month": month, "ranking": result})

    # ══════════════════════════════════════════════
    #  TTS Proxy
    # ══════════════════════════════════════════════
    def _handle_tts_proxy(self):
        try:
            data = _read_json(self)
            text = data.get("text", "").strip()
            if not text:
                self.send_response(400); self.end_headers(); return
            voice_uuid = data.get("voice_uuid", "").strip()
            model_uuid = voice_uuid if voice_uuid else AIVIS_MODEL_UUID
            audio_data = None
            source = "unknown"
            try:
                aivis_body = json.dumps({"model_uuid": model_uuid, "text": text, "output_format": "mp3"}).encode()
                aivis_req = urllib.request.Request(AIVIS_API_URL, data=aivis_body,
                    headers={"Content-Type":"application/json","Authorization":f"Bearer {AIVIS_API_KEY}"},method="POST")
                with urllib.request.urlopen(aivis_req, timeout=AIVIS_TIMEOUT) as res:
                    audio_data = res.read()
                    if len(audio_data) > 500:
                        source = "AivisCloud"
                    else:
                        audio_data = None
            except Exception:
                pass
            if audio_data is None:
                try:
                    audio_data = _edge_tts_synthesize(text)
                    source = "edge-tts"
                except Exception:
                    pass
            if audio_data and len(audio_data) > 100:
                self.send_response(200)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("Content-Length", str(len(audio_data)))
                self.end_headers()
                self.wfile.write(audio_data)
            else:
                _json_resp(self, 500, {"error": "TTS failed"})
        except Exception as e:
            _json_resp(self, 500, {"error": str(e)})

    # ══════════════════════════════════════════════
    #  Chat Proxy
    # ══════════════════════════════════════════════
    def _handle_chat_proxy(self):
        try:
            body = _read_body(self)
            req = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
                headers={"Content-Type":"application/json","Authorization":f"Bearer {OPENAI_API_KEY}"},method="POST")
            with urllib.request.urlopen(req, timeout=30) as res:
                resp_body = res.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(resp_body)))
                self.end_headers()
                self.wfile.write(resp_body)
        except urllib.error.HTTPError as e:
            err_body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
        except Exception as e:
            _json_resp(self, 500, {"error": str(e)})

    def log_message(self, fmt, *args):
        try:
            path = str(args[0]) if args else ""
            if "/api/" in path:
                print(f"[REQ] {fmt % args}")
        except Exception:
            pass

# ══════════════════════════════════════════════════════════
if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), ProxyHandler) as httpd:
        print(f"=== Vtuber Chat Server v2 ===")
        print(f"  URL:     http://0.0.0.0:{PORT}")
        print(f"  Static:  {WEB_DIR}")
        print(f"  DB:      {DB_PATH}")
        print(f"  Uploads: {UPLOAD_DIR}")
        print(f"  APIs:    /api/user/* /api/models/* /api/chat-log /api/ranking/* /api/chat /api/tts")
        httpd.serve_forever()
