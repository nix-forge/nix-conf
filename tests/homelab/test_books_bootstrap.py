"""Book onboarding blocks exposure until both services have usable accounts."""

import base64
import json
import os
import runpy
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, override
from unittest import mock

SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "hosts/nixos/desktop/local/homelab/scripts/bootstrap_books.py"
)


class BooksBootstrapTest(unittest.TestCase):
    """Exercise the real HTTP bootstrap sequence and its failure boundary."""

    # ruff: ignore[complex-structure] (the fixture keeps the two fake APIs local)
    def test_claim_reconcile_and_failed_administrator_login(self) -> None:
        """A failed re-run cannot create public readiness markers."""
        state: dict[str, Any] = {
            "claimed": False,
            "libraries": [],
            "users": [],
            "library_patches": [],
        }

        class Komga(BaseHTTPRequestHandler):
            @override
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def reply(self, status: int, value: object = None) -> None:
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                if value is not None:
                    self.wfile.write(json.dumps(value).encode())

            def authorized(self) -> bool:
                encoded = self.headers.get("Authorization", "").removeprefix("Basic ")
                if not encoded:
                    return False
                pair = base64.b64decode(encoded).decode()
                return pair in {
                    "admin@books.invalid:admin-pass",
                    "reader@books.invalid:reader-pass",
                }

            def do_GET(self) -> None:
                if self.path == "/api/v1/claim":
                    self.reply(200, {"claimed": state["claimed"]})
                elif not self.authorized():
                    self.reply(401)
                elif self.path == "/api/v1/libraries":
                    self.reply(200, state["libraries"])
                elif self.path == "/api/v2/users":
                    self.reply(200, state["users"])
                else:
                    self.reply(404)

            def do_POST(self) -> None:
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}"
                )
                if self.path == "/api/v1/claim":
                    if state["claimed"]:
                        self.reply(400)
                    else:
                        state["claimed"] = True
                        self.reply(200)
                elif not self.authorized():
                    self.reply(401)
                elif self.path == "/api/v1/libraries":
                    required = {
                        "scanCbx",
                        "scanEpub",
                        "scanPdf",
                        "scanInterval",
                        "importEpubBook",
                        "importComicInfoBook",
                    }
                    if not required <= body.keys():
                        self.reply(400)
                        return
                    library = {**body, "id": "books-id"}
                    state["libraries"].append(library)
                    self.reply(200, library)
                elif self.path == "/api/v2/users":
                    user = {
                        key: value for key, value in body.items() if key != "password"
                    }
                    shared = user.pop("sharedLibraries")
                    user["sharedAllLibraries"] = shared["all"]
                    user["sharedLibrariesIds"] = shared["libraryIds"]
                    user["id"] = "reader-id"
                    state["users"].append(user)
                    self.reply(201, user)
                else:
                    self.reply(404)

            def do_PATCH(self) -> None:
                body = json.loads(
                    self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}"
                )
                if self.authorized() and self.path == "/api/v1/libraries/books-id":
                    state["library_patches"].append(body)
                    state["libraries"][0].update(body)
                    self.reply(204)
                elif self.authorized() and self.path.endswith("/password"):
                    self.reply(204)
                else:
                    self.reply(404)

        class Audio(BaseHTTPRequestHandler):
            @override
            def log_message(self, format: str, *_args: object) -> None:
                pass

            def do_GET(self) -> None:
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"isInit":true}')

        servers = [
            ThreadingHTTPServer(("127.0.0.1", 0), Komga),
            ThreadingHTTPServer(("127.0.0.1", 0), Audio),
        ]
        for server in servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
            self.addCleanup(server.server_close)
            self.addCleanup(server.shutdown)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, password in (
                ("komga-admin-username", "admin@books.invalid"),
                ("komga-admin-password", "admin-pass"),
                ("komga-reader-username", "reader@books.invalid"),
                ("komga-reader-password", "reader-pass"),
            ):
                (root / name).write_text(password)
            ready = root / "ready"
            env = {
                **os.environ,
                "CREDENTIALS_DIRECTORY": directory,
                "BOOKS_READY_DIR": str(ready),
                "http_proxy": "http://127.0.0.1:1",
                "no_proxy": "",
            }
            argv = [
                str(SCRIPT),
                str(servers[0].server_port),
                str(servers[1].server_port),
                "/srv/media/library/books",
                "HOURLY",
            ]
            with mock.patch.dict(os.environ, env), mock.patch.object(sys, "argv", argv):
                runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertTrue((ready / "ready").exists())
                self.assertEqual(state["libraries"][0]["scanInterval"], "HOURLY")
                # An existing library keeps its other settings when policy changes.
                state["libraries"][0]["scanInterval"] = "DAILY"
                runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertEqual(state["library_patches"], [{"scanInterval": "HOURLY"}])
                self.assertEqual(state["libraries"][0]["scanInterval"], "HOURLY")
                self.assertTrue((ready / "ready").exists())
                self.assertEqual(len(state["libraries"]), 1)
                self.assertEqual(len(state["users"]), 1)
                self.assertEqual(
                    state["users"][0]["roles"], ["PAGE_STREAMING", "FILE_DOWNLOAD"]
                )
                (ready / "ready").unlink()
                (root / "komga-admin-password").write_text("wrong-admin-pass")
                with self.assertRaises(RuntimeError):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertFalse((ready / "ready").exists())
