#!/usr/bin/env python3
import http.server
import os
import subprocess
import sys
import urllib.parse

PORT = 7071

IDE_BIN = None
for candidate in [
    "/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide",
    "/usr/local/bin/cursor",
    "/usr/local/bin/code",
]:
    if os.path.exists(candidate) and os.access(candidate, os.X_OK):
        IDE_BIN = candidate
        break

def open_ide(alias, target_path):
    if not IDE_BIN:
        print("❌ No IDE binary found to launch.", file=sys.stderr)
        return
    uri = f"vscode-remote://ssh-remote+{alias}{target_path}"
    print(f"🚀 [OpenRig Host Bridge] Launching IDE attached to '{uri}'...")
    subprocess.Popen(
        [IDE_BIN, "--new-window", "--folder-uri", uri],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

class BridgeHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/open":
            params = urllib.parse.parse_qs(parsed.query)
            target_path = params.get("path", ["/workspace"])[0]
            alias = params.get("alias", ["openrig"])[0]
            open_ide(alias, target_path)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK\n")
        elif parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK\n")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/say", "/voice", "/"):
            length = int(self.headers.get("Content-Length", 0))
            text = self.rfile.read(length).decode("utf-8", errors="ignore").strip()
            if text:
                subprocess.Popen(["say", "-v", "Paulina", text])
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), BridgeHandler)
        print(f"📡 [OpenRig Host IDE Bridge] Listening on 127.0.0.1:{PORT}...")
        server.serve_forever()
    except Exception as e:
        print(f"Bridge daemon error: {e}", file=sys.stderr)
