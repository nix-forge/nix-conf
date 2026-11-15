"""Exercise startup recovery without replaying a music scan write."""

import json
import runpy
import shutil
from contextlib import nullcontext
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from subprocess import CalledProcessError  # ruff: ignore[suspicious-subprocess-import] - expected transport failure
from threading import Thread
from urllib.error import HTTPError

import pytest

SCRIPT = (
    Path(__file__).resolve().parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts/rescan_shared_music_library.py"
)


@pytest.mark.parametrize(
    "scenario", ["startup", "queued", "unauthorized", "write-failure"]
)
def test_rescan_protocol_recovery(
    tmp_path: Path, scenario: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Retry a transient read, preserve active scans and never replay writes."""
    requests: list[tuple[str, str, str | None]] = []
    posts: list[object] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            """Return a transient startup error or a fixture command list."""
            requests.append(("GET", self.path, self.headers.get("X-Api-Key")))
            if scenario == "unauthorized":
                self.send_error(HTTPStatus.UNAUTHORIZED)
                return
            if scenario == "startup" and len(requests) == 1:
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE)
                return
            commands = (
                [{"name": "RescanFolders", "status": "started"}]
                if scenario == "queued"
                else []
            )
            body = json.dumps(commands).encode()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self) -> None:
            """Record a scan command and optionally reject its write."""
            requests.append(("POST", self.path, self.headers.get("X-Api-Key")))
            posts.append(
                json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            )
            if scenario == "write-failure":
                self.send_error(HTTPStatus.SERVICE_UNAVAILABLE)
                return
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:  # ruff: ignore[builtin-argument-shadowing] - HTTP server interface
            """Keep fixture HTTP logs out of test output."""

    credentials = tmp_path / "credentials"
    credentials.mkdir()
    (credentials / "lidarr-api-key").write_text("public-fixture-api-key\n")
    curl = shutil.which("curl")
    assert curl is not None
    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            environment = {
                "CREDENTIALS_DIRECTORY": str(credentials),
                "LIDARR_URL": f"http://127.0.0.1:{server.server_port}",
                "MUSIC_ROOT": str(tmp_path / "custom music"),
                "CURL": curl,
                "HTTP_TIMEOUT_SECONDS": "2",
                "HTTP_RETRY_BUDGET_SECONDS": "4",
                "HTTP_RETRY_ATTEMPTS": "2",
            }
            for name, value in environment.items():
                monkeypatch.setenv(name, value)
            failure = {
                "unauthorized": CalledProcessError,
                "write-failure": HTTPError,
            }.get(scenario)
            with pytest.raises(failure) if failure else nullcontext():
                runpy.run_path(str(SCRIPT))
        finally:
            server.shutdown()
            thread.join(timeout=5)
    assert not thread.is_alive()
    assert all(path == "/api/v1/command" for _, path, _ in requests)
    assert all(key == "public-fixture-api-key" for _, _, key in requests)
    if scenario in {"queued", "unauthorized"}:
        assert posts == []
        assert len(requests) == 1
    else:
        assert posts == [
            {"name": "RescanFolders", "folders": [str(tmp_path / "custom music")]}
        ]
        assert len(requests) == (3 if scenario == "startup" else 2)
