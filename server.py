#!/usr/bin/env python3
"""
VTuber Chat - プロキシ + 静的ファイルサーバー
OpenAI API の CORS 問題を回避するためのプロキシエンドポイント付き
AivisCloud API (来鳥アルエ声) によるTTS対応
"""
import http.server
import socketserver
import json
import urllib.request
import urllib.error
import os
import threading

PORT = 5060
WEB_DIR = os.path.join(os.path.dirname(__file__), "build/web")

# ── APIキー設定 ──
# 環境変数 OPENAI_API_KEY を設定してから起動してください
# 例: export OPENAI_API_KEY="sk-proj-..."
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")

AIVIS_API_KEY = os.environ.get("AIVIS_API_KEY", "")

# 来鳥アルエ の AivisCloud モデルUUID
AIVIS_MODEL_UUID = os.environ.get("AIVIS_MODEL_UUID",
    "3328da9a-8124-4619-a853-f7fc2f37889f")

AIVIS_API_URL    = "https://api.aivis-project.com/v1/tts/synthesize"


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

    def _handle_tts_proxy(self):
        """TTS プロキシ: AivisCloud API (来鳥アルエ) → edge-tts フォールバック"""
        try:
            length = int(self.headers.get("Content-Length", 0))
            body   = self.rfile.read(length)
            data   = json.loads(body)
            text   = data.get("text", "").strip()

            if not text:
                self.send_response(400)
                self.end_headers()
                return

            # ── プライマリ: AivisCloud API (来鳥アルエ) ──
            if AIVIS_API_KEY:
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
                    with urllib.request.urlopen(aivis_req, timeout=20) as res:
                        resp_body = res.read()
                        if len(resp_body) > 500:
                            print(f"[TTS] AivisCloud OK: {len(resp_body)}B  '{text[:30]}'")
                            self.send_response(200)
                            self.send_header("Content-Type",   "audio/mpeg")
                            self.send_header("Content-Length", str(len(resp_body)))
                            self.end_headers()
                            self.wfile.write(resp_body)
                            return
                        else:
                            print(f"[TTS] AivisCloud レスポンス小さすぎ: {len(resp_body)}B")
                except Exception as aivis_err:
                    print(f"[TTS] AivisCloud 失敗: {aivis_err}")

            # ── フォールバック: edge-tts (rvc_server) ──
            rvc_ready = False
            try:
                with urllib.request.urlopen(
                    urllib.request.Request("http://localhost:5061/status"),
                    timeout=2
                ) as r:
                    st = json.loads(r.read())
                    rvc_ready = st.get("ready", False)
            except Exception:
                pass

            endpoint = "http://localhost:5061/tts" if rvc_ready else "http://localhost:5061/tts_mp3"
            ctype    = "audio/wav"                 if rvc_ready else "audio/mpeg"

            req = urllib.request.Request(
                endpoint,
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=60) as res:
                resp_body = res.read()
                print(f"[TTS] edge-tts fallback: {len(resp_body)}B")
                self.send_response(200)
                self.send_header("Content-Type",   ctype)
                self.send_header("Content-Length", str(len(resp_body)))
                self.end_headers()
                self.wfile.write(resp_body)

        except Exception as e:
            print(f"[TTS] ERROR: {e}")
            msg = json.dumps({"error": str(e)}).encode()
            self.send_response(500)
            self.send_header("Content-Type",   "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

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
                print(f"[CHAT] → OpenAI | user: '{last_user}'")
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
                    print(f"[CHAT] ← AI: '{ai_text}'")
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
        # API以外の静的ファイルリクエストはログ抑制
        path = args[0] if args else ""
        if "/api/" in path:
            print(f"[REQ] {fmt % args}")


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), ProxyHandler) as httpd:
        print(f"✅ Vtuber Chat Server  http://0.0.0.0:{PORT}")
        print(f"📁 Static: {WEB_DIR}")
        print(f"🤖 Chat:   POST /api/chat  → OpenAI gpt-4o")
        print(f"🎤 TTS:    POST /api/tts   → AivisCloud (来鳥アルエ) + edge-tts fallback")
        print(f"🔑 OpenAI key: {'SET' if OPENAI_API_KEY else 'MISSING'}")
        print(f"🔑 Aivis  key: {'SET' if AIVIS_API_KEY  else 'MISSING'}")
        httpd.serve_forever()
