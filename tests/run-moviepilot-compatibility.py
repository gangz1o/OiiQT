"""Exercise the production API clients with V2 and OpenAPI V3.1.9 HTTP fixtures.

Reference: https://api.movie-pilot.org/openapi.json
Run: python3 tests/run-moviepilot-compatibility.py
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
from urllib.parse import urlsplit, parse_qs, unquote
import json
import subprocess


class FixtureServer(BaseHTTPRequestHandler):
    requests = []

    def log_message(self, *_):
        pass

    def respond(self, status, payload):
        data = payload.encode() if isinstance(payload, str) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.handle_api()

    def do_POST(self):
        self.handle_api()

    def handle_api(self):
        url = urlsplit(self.path)
        scenario, path = unquote(url.path).lstrip("/").split("/", 1)
        query = parse_qs(url.query)
        self.requests.append((scenario, self.command, path))
        if self.command == "POST":
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        authorized = (self.headers.get("X-API-KEY") == "fixture-api-key"
                      or self.headers.get("Authorization") == "Bearer fixture-access-token"
                      or query.get("apikey") == ["fixture-query-key"]
                      or query.get("token") == ["fixture-query-token"])
        if not authorized or scenario == "unauthorized":
            self.respond(401, {"success": False, "message": "Invalid credential", "data": None})
            return
        if scenario == "download-failure":
            self.respond(500, {"success": False, "message": "Download failed", "data": None})
            return
        if scenario in ["business-failure", "failed-detail"]:
            self.respond(200, {"success": False, "message": "Fixture failure", "data": {"name": "Not a valid result"}})
            return
        if scenario in ["null-user", "null-detail"]:
            self.respond(200, {"success": True, "message": "", "data": None})
            return
        if scenario == "html":
            self.respond(200, "<html>Proxy login</html>")
            return

        media = {"title": "Fixture Movie", "media_id": "123", "type": "电影", "year": "2026"}
        media["media_source" if scenario == "v3" else "source"] = "themoviedb" if scenario == "v3" else "tmdb"
        if path == "api/v1/user/current":
            result = {"id": 7, "name": "Fixture User"}
        elif path == "api/v1/recommend/source":
            result = [{"name": "TMDB", "api_path": "/api/v1/recommend/tmdb_movies", "type": "电影"}]
        elif path in ["api/v1/recommend/tmdb_movies", "api/v1/media/search"]:
            result = [media]
        elif path.startswith(("api/v1/media/", "api/v1/search/media/")):
            if scenario == "v3" and "media_source" not in query:
                self.respond(422, {"success": False, "message": "media_source is required", "data": []})
                return
            expected = "123" if scenario == "v3" else "tmdb:123"
            if path.split("/")[-1] != expected or (scenario == "v3" and query.get("media_source") != ["themoviedb"]):
                self.respond(400, {"success": False, "message": "Wrong media identity", "data": None})
                return
            result = [{"torrent_info": {"title": "Fixture Release", "future_field": "preserve-me"}}] if "/search/" in path else media
        elif path.startswith("api/v1/tmdb/credits/"):
            result = [{"id": 1, "name": "Fixture Actor"}]
        elif path == "api/v1/download/clients":
            result = [{"name": "Fixture Downloader", "type": "qbittorrent"}]
        elif path == "api/v1/download/add":
            assert body["torrent_in"]["future_field"] == "preserve-me"
            self.respond(200, {"success": True, "message": "Added", "data": {"download_id": "fixture"}})
            return
        else:
            self.respond(404, {"detail": "Not Found"})
            return
        if scenario == "v3":
            result = {"success": True, "message": "", "data": result}
        self.respond(200, result)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureServer)
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        with TemporaryDirectory(prefix="oiiqt-mp-tests-") as output:
            binary = str(Path(output) / "compatibility-tests")
            sources = ["models/MoviePilotServer.swift", "services/MoviePilotAPIClient.swift",
                       "services/MoviePilotResponseDecoder.swift", "services/MoviePilotDiscoveryAPI.swift",
                       "services/MoviePilotMediaDetailAPI.swift", "services/MoviePilotDiscoveryDTO.swift",
                       "services/MoviePilotMediaDetailDTO.swift"]
            subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                            *[str(root / "OiiQT" / path) for path in sources],
                            str(root / "tests/MoviePilotCompatibilityTests.swift"), "-o", binary], check=True)
            subprocess.run([binary, f"http://127.0.0.1:{server.server_port}"], check=True)
            expected_requests = {"business-failure": 1, "html": 1, "null-user": 1,
                                 "failed-detail": 2, "null-detail": 2, "download-failure": 1,
                                 "unauthorized": 4}
            for scenario, count in expected_requests.items():
                assert sum(item[0] == scenario for item in FixtureServer.requests) == count, scenario
            print("Non-authentication errors were not retried; download submitted only once")
    finally:
        server.shutdown()
        server.server_close()
