import http.server
import json
import os
import socketserver
from datetime import datetime


SCRIPT_ROOT = os.path.dirname(os.path.abspath(__file__))
RUNTIME_ROOT = os.path.join(SCRIPT_ROOT, "sandbox", "runtime", "webhook-sink")
LOG_FILE = os.path.join(RUNTIME_ROOT, "webhook-sink.log")
PORT = int(os.environ.get("DURESS_WEBHOOK_SINK_PORT", "8065"))


def ensure_runtime():
    os.makedirs(RUNTIME_ROOT, exist_ok=True)


def log_entry(kind: str, payload: str) -> None:
    ensure_runtime()
    with open(LOG_FILE, "a", encoding="utf-8") as handle:
        handle.write(f"{datetime.now():%Y-%m-%d %H:%M:%S.%f} {kind} {payload}\n")


class WebhookSinkHandler(http.server.BaseHTTPRequestHandler):
    server_version = "DuressLocalWebhookSink/1.0"

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        try:
            compact = json.dumps(json.loads(body), separators=(",", ":"))
        except Exception:
            compact = body

        log_entry("POST", f"path={self.path} body={compact}")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{\"ok\":true}")

    def log_message(self, fmt, *args):
        log_entry("HTTP", fmt % args)


def main():
    ensure_runtime()
    with socketserver.TCPServer(("127.0.0.1", PORT), WebhookSinkHandler) as httpd:
        log_entry("INFO", f"webhook sink listening on 127.0.0.1:{PORT}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
