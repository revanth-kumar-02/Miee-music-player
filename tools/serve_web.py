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
