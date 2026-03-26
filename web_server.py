#!/usr/bin/env python3
"""
Web preview server with API proxy for /api/chat (OpenAI) and /api/tts (AIVIS).
Serves Flutter web build from build/web/ and proxies API calls.
"""
import http.server
import socketserver
import json
import os
import sys
import urllib.request
import urllib.error

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5060
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')

# Load API keys from env files
OPENAI_API_KEY = ''
AIVIS_API_KEY = ''
AIVIS_MODEL_UUID = 'a670e6b8-0852-45b2-8704-1bc9862f2fe6'
AIVIS_SPEAKER_UUID = 'b1ca560f-f212-4e67-ab7d-0a4f5afb75a8'

def load_env():
    global OPENAI_API_KEY, AIVIS_API_KEY
    for env_path in [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env'),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), 'web', 'env.txt'),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets', 'webapp', 'env.txt'),
    ]:
        if os.path.exists(env_path):
            with open(env_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if '=' in line:
                        key, val = line.split('=', 1)
                        key = key.strip()
                        val = val.strip()
                        if key == 'OPENAI_API_KEY':
                            OPENAI_API_KEY = val
                        elif key == 'AIVIS_API_KEY':
                            AIVIS_API_KEY = val
            if OPENAI_API_KEY and AIVIS_API_KEY:
                print(f"Loaded API keys from {env_path}")
                return
    print("Warning: Could not find all API keys in env files")

load_env()

class APIProxyHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        if self.path == '/api/chat':
            self._proxy_chat()
        elif self.path == '/api/tts':
            self._proxy_tts()
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

    def _proxy_chat(self):
        """Proxy /api/chat to OpenAI API"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            req = urllib.request.Request(
                'https://api.openai.com/v1/chat/completions',
                data=body,
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {OPENAI_API_KEY}',
                },
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

    def _proxy_tts(self):
        """Proxy /api/tts to AIVIS TTS API"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            data = json.loads(body)
            text = data.get('text', '').strip()

            if not text:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'Empty text')
                return

            aivis_body = json.dumps({
                'model_uuid': AIVIS_MODEL_UUID,
                'speaker_uuid': AIVIS_SPEAKER_UUID,
                'text': text,
                'speed': 1.0,
                'output_format': 'mp3',
            }).encode()

            req = urllib.request.Request(
                'https://api.aivis-project.com/v1/tts/synthesize',
                data=aivis_body,
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {AIVIS_API_KEY}',
                },
                method='POST'
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                audio_data = resp.read()
                if len(audio_data) > 500:
                    self.send_response(200)
                    self.send_header('Content-Type', 'audio/mpeg')
                    self.send_header('X-TTS-Source', 'AivisCloud')
                    self.end_headers()
                    self.wfile.write(audio_data)
                else:
                    self.send_response(500)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'error': 'TTS response too small'}).encode())
        except urllib.error.HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

if __name__ == '__main__':
    print(f"Starting server on port {PORT}, serving {WEB_DIR}")
    print(f"OpenAI key: {OPENAI_API_KEY[:15]}..." if OPENAI_API_KEY else "OpenAI key: NOT SET")
    print(f"AIVIS key: {AIVIS_API_KEY[:15]}..." if AIVIS_API_KEY else "AIVIS key: NOT SET")

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(('0.0.0.0', PORT), APIProxyHandler) as httpd:
        print(f"Server running at http://0.0.0.0:{PORT}")
        httpd.serve_forever()
