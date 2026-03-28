#!/usr/bin/env python3
"""
VTuber Chat - プロキシ + 静的ファイルサーバー
OpenAI API の CORS 問題を回避するためのプロキシエンドポイント付き
AivisCloud API (来鳥アルエ声) によるTTS対応 + edge-tts フォールバック
"""
import http.server
import socketserver
import json
import urllib.request
import urllib.error
import os
import asyncio
import io
import threading

PORT = 5060
WEB_DIR = os.path.join(os.path.dirname(__file__), "build/web")

# ══════════════════════════════════════════════════════════
#  APIキー (環境変数 → .env ファイル → フォールバック)
# ══════════════════════════════════════════════════════════
def _load_env_file():
    """Load .env file if present (overrides existing env vars)"""
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    os.environ[k.strip()] = v.strip()  # .envファイルを優先
_load_env_file()

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
AIVIS_API_KEY  = os.environ.get("AIVIS_API_KEY", "")

# 来鳥アルエ の AivisCloud モデルUUID
AIVIS_MODEL_UUID = "a670e6b8-0852-45b2-8704-1bc9862f2fe6"
AIVIS_API_URL    = "https://api.aivis-project.com/v1/tts/synthesize"
AIVIS_TIMEOUT    = 5   # AivisCloud のタイムアウト (秒) - フォールバック速度優先

# edge-tts フォールバック設定
EDGE_TTS_VOICE = "ja-JP-NanamiNeural"


def _edge_tts_synthesize(text):
    """edge-tts で音声合成 (同期ラッパー)"""
    import edge_tts

    async def _synth():
        comm = edge_tts.Communicate(text, voice=EDGE_TTS_VOICE)
        buf = io.BytesIO()
        async for chunk in comm.stream():
            if chunk["type"] == "audio":
                buf.write(chunk["data"])
        return buf.getvalue()

    # スレッドごとに新しいイベントループを作成
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(_synth())
    finally:
        loop.close()


class ProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
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

    def do_POST(self):
        if self.path == "/api/chat":
            self._handle_chat_proxy()
        elif self.path == "/api/tts":
            self._handle_tts_proxy()
        else:
            self.send_response(404)
            self.end_headers()

    # ══════════════════════════════════════════════════════
    #  TTS: AivisCloud API (来鳥アルエ) + edge-tts フォールバック
    # ══════════════════════════════════════════════════════
    def _handle_tts_proxy(self):
        """TTS プロキシ: AivisCloud API 優先、失敗時 edge-tts フォールバック"""
        try:
            length = int(self.headers.get("Content-Length", 0))
            body   = self.rfile.read(length)
            data   = json.loads(body)
            text   = data.get("text", "").strip()

            if not text:
                self.send_response(400)
                self.end_headers()
                return

            audio_data = None
            source = "unknown"

            # ── 1. AivisCloud API を試行 ──
            try:
                aivis_body = json.dumps({
                    "model_uuid": AIVIS_MODEL_UUID,
                    "text": text,
                    "output_format": "mp3",
                }).encode("utf-8")

                aivis_req = urllib.request.Request(
                    AIVIS_API_URL,
                    data=aivis_body,
                    headers={
                        "Content-Type":  "application/json",
                        "Authorization": f"Bearer {AIVIS_API_KEY}",
                    },
                    method="POST",
                )
                with urllib.request.urlopen(aivis_req, timeout=AIVIS_TIMEOUT) as res:
                    audio_data = res.read()
                    if len(audio_data) > 500:
                        source = "AivisCloud"
                        print(f"[TTS] AivisCloud OK: {len(audio_data)}B  '{text[:30]}'")
                    else:
                        print(f"[TTS] AivisCloud response too small ({len(audio_data)}B), falling back")
                        audio_data = None
            except Exception as aivis_err:
                print(f"[TTS] AivisCloud failed: {aivis_err} -> edge-tts fallback")

            # ── 2. edge-tts フォールバック ──
            if audio_data is None:
                try:
                    audio_data = _edge_tts_synthesize(text)
                    source = "edge-tts"
                    print(f"[TTS] edge-tts OK: {len(audio_data)}B  '{text[:30]}'")
                except Exception as edge_err:
                    print(f"[TTS] edge-tts also failed: {edge_err}")

            # ── 3. レスポンス送信 ──
            if audio_data and len(audio_data) > 100:
                self.send_response(200)
                self.send_header("Content-Type",   "audio/mpeg")
                self.send_header("Content-Length", str(len(audio_data)))
                self.send_header("X-TTS-Source",   source)
                self.end_headers()
                self.wfile.write(audio_data)
            else:
                msg = json.dumps({"error": "All TTS engines failed"}).encode()
                self.send_response(500)
                self.send_header("Content-Type",   "application/json")
                self.send_header("Content-Length", str(len(msg)))
                self.end_headers()
                self.wfile.write(msg)

        except Exception as e:
            print(f"[TTS] ERROR: {e}")
            msg = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    # ══════════════════════════════════════════════════════
    #  Chat: OpenAI API プロキシ
    # ══════════════════════════════════════════════════════
    def _handle_chat_proxy(self):
        """OpenAI Chat API プロキシ"""
        try:
            length = int(self.headers.get("Content-Length", 0))
            body   = self.rfile.read(length)

            # リクエストボディをパースしてログ
            try:
                req_data = json.loads(body)
                msgs = req_data.get("messages", [])
                last_user = next(
                    (m["content"][:40] for m in reversed(msgs) if m.get("role") == "user"),
                    ""
                )
                print(f"[CHAT] -> OpenAI | user: '{last_user}'")
            except Exception:
                pass

            req = urllib.request.Request(
                "https://api.openai.com/v1/chat/completions",
                data=body,
                headers={
                    "Content-Type":  "application/json",
                    "Authorization": f"Bearer {OPENAI_API_KEY}",
                },
                method="POST",
            )

            with urllib.request.urlopen(req, timeout=30) as res:
                resp_body = res.read()
                # レスポンスをログ
                try:
                    rd = json.loads(resp_body)
                    ai_text = rd["choices"][0]["message"]["content"][:60]
                    print(f"[CHAT] <- AI: '{ai_text}'")
                except Exception:
                    pass
                self.send_response(200)
                self.send_header("Content-Type",   "application/json")
                self.send_header("Content-Length", str(len(resp_body)))
                self.end_headers()
                self.wfile.write(resp_body)

        except urllib.error.HTTPError as e:
            err_body = e.read()
            print(f"[CHAT] HTTPError {e.code}: {err_body[:200]}")
            self.send_response(e.code)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
        except Exception as e:
            print(f"[CHAT] ERROR: {e}")
            msg = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def log_message(self, fmt, *args):
        try:
            path = str(args[0]) if args else ""
            if "/api/" in path:
                print(f"[REQ] {fmt % args}")
        except Exception:
            pass


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), ProxyHandler) as httpd:
        print(f"=== Vtuber Chat Server  http://0.0.0.0:{PORT} ===")
        print(f"  Static: {WEB_DIR}")
        print(f"  Chat:   POST /api/chat  -> OpenAI gpt-4o")
        print(f"  TTS:    POST /api/tts   -> AivisCloud ({AIVIS_MODEL_UUID[:8]}...) + edge-tts fallback")
        print(f"  OpenAI key: {OPENAI_API_KEY[:12]}...{OPENAI_API_KEY[-4:]}")
        print(f"  Aivis  key: {AIVIS_API_KEY[:12]}...{AIVIS_API_KEY[-4:]}")
        print(f"  Aivis timeout: {AIVIS_TIMEOUT}s  |  edge-tts voice: {EDGE_TTS_VOICE}")
        httpd.serve_forever()
