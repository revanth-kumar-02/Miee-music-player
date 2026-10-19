import http.server
import mimetypes
import os
import socketserver
import sys

# Ensure correct MIME types for modern web
mimetypes.init()
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('application/javascript', '.mjs')
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('application/json', '.json')

BUILD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'build', 'web'))

YT_PORT = 8089
_yt_process = None

def ensure_yt_service():
    global _yt_process
    import urllib.request
    import time
    import subprocess

    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{YT_PORT}/api/yt/health', timeout=1) as resp:
            if resp.status == 200:
                return True
    except Exception:
        pass

    tools_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(tools_dir, '..'))
    cmd = [
        'dart',
        '--packages=.dart_tool/package_config.json',
        'run',
        os.path.join(tools_dir, 'yt_service.dart'),
        str(YT_PORT),
    ]
    try:
        _yt_process = subprocess.Popen(cmd, cwd=repo_root)
        for _ in range(30):
            time.sleep(0.1)
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{YT_PORT}/api/yt/health', timeout=1) as resp:
                    if resp.status == 200:
                        return True
            except Exception:
                pass
    except Exception as e:
        print(f"[serve_web] Failed to launch YT backend: {e}")
        return False
    return True

class FlutterSpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def do_OPTIONS(self):
        if self.path.startswith('/api/'):
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', '*')
            self.end_headers()
            return
        return super().do_OPTIONS()

    def do_GET(self):
        # Dedicated CORS-free backend discovery & stream resolution proxy
        if self.path.startswith('/api/yt/') or self.path.startswith('/api/search'):
            import urllib.request
            ensure_yt_service()
            try:
                target_url = f"http://127.0.0.1:{YT_PORT}{self.path}"
                req = urllib.request.Request(target_url)
                with urllib.request.urlopen(req, timeout=15) as resp:
                    content = resp.read()
                    status = resp.status
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', '*')
                self.end_headers()
                self.wfile.write(content)
                return
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                err_msg = str(e).encode('utf-8')
                self.wfile.write(b'{"error": "' + err_msg + b'"}')
                return

        return super().do_GET()

    def send_head(self):
        # Resolve target filesystem path
        clean_path = self.path.split('?')[0].split('#')[0]
        local_path = os.path.normpath(os.path.join(BUILD_DIR, clean_path.lstrip('/')))

        # If file exists on disk, serve it directly with proper MIME type
        if os.path.isfile(local_path):
            return super().send_head()

        # If it's a directory with index.html, serve that directory
        if os.path.isdir(local_path) and os.path.isfile(os.path.join(local_path, 'index.html')):
            return super().send_head()

        # If a file with an extension was requested but does not exist, return 404
        # (Crucial: do NOT return index.html for missing .js or .wasm files)
        _, ext = os.path.splitext(clean_path)
        if ext:
            self.send_error(404, f"File not found: {clean_path}")
            return None

        # Single-page application route fallback (e.g. /home, /library -> /index.html)
        self.path = '/index.html'
        return super().send_head()

    def end_headers(self):
        # Prevent stale caching during development
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        # Standard Cross-Origin headers for CanvasKit/Skwasm if needed
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'credentialless')
        super().end_headers()

class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

def run(port=3000):
    handler = FlutterSpaHandler
    with ThreadingTCPServer(('0.0.0.0', port), handler) as httpd:
        print(f"Serving Flutter Web at http://localhost:{port} from {BUILD_DIR}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    run(port)
