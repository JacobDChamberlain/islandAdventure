#!/usr/bin/env python3
"""Serve the exported web build locally for testing.

    python3 tools/serve_web.py          # then open http://localhost:8060

A plain `python3 -m http.server` is NOT enough. The web export is built with
thread support, which needs SharedArrayBuffer, which browsers only hand out to
pages served "cross-origin isolated" -- meaning these two headers must be
present. Without them the canvas stays blank and the console complains about
SharedArrayBuffer being undefined. This is the same isolation that the
"SharedArrayBuffer support" checkbox turns on for an itch.io page.
"""
import argparse
import http.server
import os
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Godot ships .wasm and .pck; a wrong MIME type on the wasm makes the
        # browser refuse to stream-compile it.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        # Quieten the per-request spam, but keep errors visible.
        if not str(args[1] if len(args) > 1 else "").startswith("2"):
            super().log_message(fmt, *args)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8060)
    ap.add_argument("--dir", default="build/web")
    a = ap.parse_args()
    if not os.path.isfile(os.path.join(a.dir, "index.html")):
        raise SystemExit(
            "No build found in %s.\nExport one first:\n"
            "  \"$GD\" --headless --path . --export-release \"Web\" build/web/index.html"
            % a.dir)
    os.chdir(a.dir)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", a.port), Handler) as httpd:
        print("Serving %s at http://localhost:%d  (Ctrl-C to stop)" % (a.dir, a.port))
        httpd.serve_forever()
