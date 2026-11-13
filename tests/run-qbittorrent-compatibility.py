"""Run the production Swift authentication code against local HTTP fixtures.

Contracts: qBittorrent release-5.2.3 authcontroller.cpp/webapplication.cpp,
and the legacy 5.0 WebUI API documentation. No real server credentials needed.
Run: python3 tests/run-qbittorrent-compatibility.py
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
from urllib.parse import parse_qs
import subprocess


class FixtureServer(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, body="", cookie=None):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        scenario = self.path.split("/")[1]
        if not self.path.endswith("/api/v2/auth/login") or scenario == "bearer":
            self.respond(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if parse_qs(body) != {"username": ["tester"], "password": ["test +&=%密碼"]}:
            self.respond(401)
            return
        cookie_name = {"legacy": "SID", "custom-cookie": "custom_session"}.get(scenario, "QBT_SID_fixture")
        cookie = f"{cookie_name}=fixture; HttpOnly; Path=/{scenario}/"
        responses = {
            "legacy": (200, "Ok.", cookie),
            "modern": (204, "", cookie),
            "empty200": (200, "", cookie),
            "custom-cookie": (204, "", cookie),
            "wrong-password": (401, "Unauthorized", None),
            "legacy-failure": (200, "Fails.", cookie),
            "proxy-html": (200, "<html>Sign in to the proxy</html>", cookie),
            "missing-session": (204, "", None),
            "banned": (403, "Forbidden", None),
            "wrong-path": (404, "Not Found", None),
        }
        self.respond(*responses[scenario])

    def do_GET(self):
        scenario = self.path.split("/")[1]
        if not self.path.endswith("/api/v2/app/version"):
            self.respond(404)
            return
        if scenario == "bearer":
            authorized = self.headers.get("Authorization") == "Bearer qbt_test_key"
        else:
            cookie_name = {"legacy": "SID", "custom-cookie": "custom_session"}.get(scenario, "QBT_SID_fixture")
            authorized = f"{cookie_name}=fixture" in self.headers.get("Cookie", "")
        self.respond(200, "v5.0.0" if scenario == "legacy" else "v5.2.3") if authorized else self.respond(403)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureServer)
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        with TemporaryDirectory(prefix="oiiqt-qb-tests-") as output:
            binary = str(Path(output) / "compatibility-tests")
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                str(root / "OiiQT/services/QBittorrentAPI.swift"),
                str(root / "tests/QBittorrentAPICompatibilityTests.swift"), "-o", binary,
            ], check=True)
            subprocess.run([binary, f"http://127.0.0.1:{server.server_port}"], check=True)
    finally:
        server.shutdown()
        server.server_close()
