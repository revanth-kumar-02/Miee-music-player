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

class FlutterSpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def do_GET(self):
        # Dedicated CORS-free backend discovery proxy
        if self.path.startswith('/api/search'):
            import urllib.parse
            import urllib.request
            parsed = urllib.parse.urlparse(self.path)
            params = urllib.parse.parse_qs(parsed.query)
            query = params.get('q', [''])[0].strip()
            if not query:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(b'{"results":[]}')
                return

            try:
                enc = urllib.parse.quote(query)
                lim = params.get('limit', ['25'])[0]
                url = f"https://itunes.apple.com/search?term={enc}&entity=song&limit={lim}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Miee-Backend/1.0'})
                with urllib.request.urlopen(req, timeout=10) as resp:
                    content = resp.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
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
