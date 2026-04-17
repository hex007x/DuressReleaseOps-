import html
import http.server
import os
import socketserver
import urllib.parse
from datetime import datetime


SCRIPT_ROOT = os.path.dirname(os.path.abspath(__file__))
RUNTIME_ROOT = os.path.join(SCRIPT_ROOT, "sandbox", "runtime", "license-portal")
ACTIVE_MODE_FILE = os.path.join(RUNTIME_ROOT, "active-mode.txt")
CURRENT_LICENSE_FILE = os.path.join(RUNTIME_ROOT, "current-license.xml")
RENEWED_LICENSE_FILE = os.path.join(RUNTIME_ROOT, "renewed-license.xml")
INVALID_LICENSE_FILE = os.path.join(RUNTIME_ROOT, "invalid-license.xml")
LOG_FILE = os.path.join(RUNTIME_ROOT, "license-portal.log")
PORT = int(os.environ.get("DURESS_LICENSE_PORTAL_PORT", "8055"))
TOKEN = os.environ.get("DURESS_LICENSE_PORTAL_TOKEN", "")


def ensure_runtime():
    os.makedirs(RUNTIME_ROOT, exist_ok=True)


def log_line(message: str) -> None:
    ensure_runtime()
    with open(LOG_FILE, "a", encoding="utf-8") as handle:
        handle.write(f"{datetime.now():%Y-%m-%d %H:%M:%S.%f} {message}\n")


def read_text(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().lstrip("\ufeff")


def read_mode() -> str:
    mode = read_text(ACTIVE_MODE_FILE).strip()
    return mode or "current"


def xml_escape(value: str) -> str:
    return html.escape(value or "")


class LicensePortalHandler(http.server.BaseHTTPRequestHandler):
    server_version = "DuressLocalLicensePortal/1.0"

    def do_POST(self):
        if self.path.rstrip("/") != "/licenses/check-in":
            self.send_error(404)
            return

        if TOKEN:
            request_token = self.headers.get("X-Duress-License-Token", "")
            if request_token != TOKEN:
                log_line("rejected request with invalid token")
                self.send_error(403)
                return

        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length).decode("utf-8", errors="replace")
        form = urllib.parse.parse_qs(raw_body, keep_blank_values=True)
        mode = read_mode()

        license_xml = ""
        status = "Current"
        message = "License is current."

        if mode == "renewed":
            license_xml = read_text(RENEWED_LICENSE_FILE)
            status = "Renewed"
            message = "A renewed license is available."
        elif mode == "invalid":
            license_xml = read_text(INVALID_LICENSE_FILE)
            status = "Renewed"
            message = "A renewed license is available."
        elif mode == "error":
            log_line(
                "check-in "
                f"mode={mode} "
                f"license_id={form.get('license_id', [''])[0]} "
                f"fingerprint={form.get('server_fingerprint', [''])[0]} "
                f"version={form.get('version', [''])[0]}"
            )
            response_xml = (
                '<?xml version="1.0" encoding="utf-8"?>\n'
                "<LicenseCheckResponse>\n"
                "  <Status>Error</Status>\n"
                "  <Message>Temporary upstream licensing error.</Message>\n"
                "  <LicenseXml></LicenseXml>\n"
                "</LicenseCheckResponse>\n"
            )
            response_bytes = response_xml.encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/xml; charset=utf-8")
            self.send_header("Content-Length", str(len(response_bytes)))
            self.end_headers()
            self.wfile.write(response_bytes)
            return
        else:
            status = "Current"
            message = "License is current."

        log_line(
            "check-in "
            f"mode={mode} "
            f"license_id={form.get('license_id', [''])[0]} "
            f"fingerprint={form.get('server_fingerprint', [''])[0]} "
            f"version={form.get('version', [''])[0]}"
        )

        response_xml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<LicenseCheckResponse>\n"
            f"  <Status>{xml_escape(status)}</Status>\n"
            f"  <Message>{xml_escape(message)}</Message>\n"
            f"  <LicenseXml>{xml_escape(license_xml)}</LicenseXml>\n"
            "</LicenseCheckResponse>\n"
        )

        response_bytes = response_xml.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(response_bytes)))
        self.end_headers()
        self.wfile.write(response_bytes)

    def log_message(self, fmt, *args):
        log_line("http " + (fmt % args))


def main():
    ensure_runtime()
    with socketserver.TCPServer(("127.0.0.1", PORT), LicensePortalHandler) as httpd:
        log_line(f"portal listening on 127.0.0.1:{PORT}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
