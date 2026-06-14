#!/usr/bin/env python3
# Local dev server for the map editor.
#   GET  /maptool/editor.html , /v0.3.p8 , ...   (static files)
#   POST /save                                   (writes body -> v0.3.p8)
# Serves from the cortex_override/ dir so the editor can auto-load
# v0.3.p8 and write it back directly (no download step).
import http.server, os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # -> cortex_override/

class H(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/save':
            n = int(self.headers.get('Content-Length', 0))
            open('v0.3.p8', 'wb').write(self.rfile.read(n))
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
            print('saved v0.3.p8')
        else:
            self.send_error(404)
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')  # always reload latest cart
        super().end_headers()

H.extensions_map['.p8'] = 'text/plain'
print('editor server on http://localhost:8765  (Export writes v0.3.p8)')
http.server.HTTPServer(('127.0.0.1', 8765), H).serve_forever()
