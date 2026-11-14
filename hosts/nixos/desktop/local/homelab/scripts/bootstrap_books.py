"""Claim and reconcile the private Komga library before exposing book sites."""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def _credential(name: str) -> str:
    path = Path(os.environ["CREDENTIALS_DIRECTORY"]) / name
    value = path.read_text().strip()
    if not value or any(character in value for character in "\r\n\0"):
        message = f"Invalid {name} credential"
        raise TypeError(message)
    return value


class _HttpStatusError(RuntimeError):
    def __init__(self, method: str, path: str, status: int) -> None:
        self.status = status
        super().__init__(f"{method} {path} returned HTTP {status}")


class _Client:
    def __init__(
        self,
        base: str,
        username: str = "",
        password: str = "",
    ) -> None:
        self.base = base
        self.username = username
        self.password = password

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
        expected: tuple[int, ...] = (200,),
    ) -> dict[str, Any] | list[dict[str, Any]] | None:
        request_headers = dict(headers or {})
        if self.username:
            pair = f"{self.username}:{self.password}".encode()
            request_headers["Authorization"] = (
                "Basic " + base64.b64encode(pair).decode()
            )
        if body is not None:
            request_headers["Content-Type"] = "application/json"
        r = urllib.request.Request(  # ruff: ignore[suspicious-url-open-usage]
            self.base + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers=request_headers,
            method=method,
        )
        # Ignore proxy environment variables even for requests to loopback.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            response = opener.open(r, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            status = response.status
            if status is None:
                message = "The HTTP response did not provide a status"
                raise RuntimeError(message)
            if status not in expected:
                raise _HttpStatusError(method, path, status)
            data = response.read()
            return json.loads(data) if data else None


def _object(value: object) -> dict[str, Any]:
    if not isinstance(value, dict):
        message = "The service returned an invalid JSON object"
        raise TypeError(message)
    return value


def _objects(value: object) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        message = "The service returned an invalid JSON object list"
        raise TypeError(message)
    return [_object(item) for item in value]


def _wait_for_komga(client: _Client) -> None:
    deadline = time.monotonic() + 120
    while True:
        try:
            client.request("GET", "/api/v1/claim")
        except urllib.error.URLError:
            if time.monotonic() >= deadline:
                message = "Komga did not start within two minutes"
                raise RuntimeError(message) from None
            time.sleep(2)
        else:
            return


def _library(admin: _Client, books: str, scan_interval: str) -> str:
    libraries = _objects(admin.request("GET", "/api/v1/libraries"))
    matches = [item for item in libraries if item["name"] == "Books"]
    if len(matches) > 1:
        message = "Ambiguous Komga Books library"
        raise RuntimeError(message)
    if matches:
        library = matches[0]
        if library["root"] != books:
            message = "Komga Books library points to a different root"
            raise RuntimeError(message)
        if library.get("scanInterval") != scan_interval:
            admin.request(
                "PATCH",
                f"/api/v1/libraries/{library['id']}",
                {"scanInterval": scan_interval},
                expected=(204,),
            )
    else:
        library = admin.request(
            "POST",
            "/api/v1/libraries",
            {
                "name": "Books",
                "root": books,
                "analyzeDimensions": False,
                "convertToCbz": False,
                "emptyTrashAfterScan": False,
                "hashFiles": False,
                "hashKoreader": False,
                "hashPages": False,
                "importBarcodeIsbn": True,
                "importComicInfoBook": True,
                "importComicInfoCollection": True,
                "importComicInfoReadList": True,
                "importComicInfoSeries": True,
                "importComicInfoSeriesAppendVolume": True,
                "importEpubBook": True,
                "importEpubSeries": True,
                "importLocalArtwork": True,
                "importMylarSeries": False,
                "repairExtensions": False,
                "scanCbx": True,
                "scanDirectoryExclusions": [],
                "scanEpub": True,
                "scanForceModifiedTime": False,
                "scanInterval": scan_interval,
                "scanOnStartup": True,
                "scanPdf": True,
                "seriesCover": "FIRST",
            },
        )
    return _object(library)["id"]


def _reader(admin: _Client, library_id: str, username: str, password: str) -> None:
    policy = {
        "roles": ["PAGE_STREAMING", "FILE_DOWNLOAD"],
        "sharedLibraries": {"all": False, "libraryIds": [library_id]},
    }
    users = _objects(admin.request("GET", "/api/v2/users"))
    matches = [item for item in users if item["email"] == username]
    if len(matches) > 1:
        message = "Ambiguous Komga reader account"
        raise RuntimeError(message)
    if matches:
        user = matches[0]
        if (
            set(user["roles"]) != set(policy["roles"])
            or user["sharedAllLibraries"] is not False
            or set(user["sharedLibrariesIds"]) != {library_id}
        ):
            admin.request(
                "PATCH", f"/api/v2/users/{user['id']}", policy, expected=(204,)
            )
        admin.request(
            "PATCH",
            f"/api/v2/users/{user['id']}/password",
            {"password": password},
            expected=(204,),
        )
    else:
        admin.request(
            "POST",
            "/api/v2/users",
            {"email": username, "password": password, **policy},
            expected=(201,),
        )
    reader = _Client(admin.base, username, password)
    reader.request("GET", "/api/v1/libraries")


def _reconcile(
    komga_port: int, audiobookshelf_port: int, books: str, scan_interval: str
) -> None:
    if scan_interval not in {
        "DISABLED",
        "HOURLY",
        "EVERY_6H",
        "EVERY_12H",
        "DAILY",
        "WEEKLY",
    }:
        message = "Invalid Komga scan interval"
        raise ValueError(message)
    admin_password = _credential("komga-admin-password")
    admin_email = _credential("komga-admin-username")
    reader_password = _credential("komga-reader-password")
    reader_email = _credential("komga-reader-username")
    unauthenticated = _Client(f"http://127.0.0.1:{komga_port}")
    _wait_for_komga(unauthenticated)
    admin = _Client(unauthenticated.base, admin_email, admin_password)
    try:
        admin.request("GET", "/api/v1/libraries")
    except _HttpStatusError as error:
        if error.status not in {401, 403}:
            raise
        unauthenticated.request(
            "POST",
            "/api/v1/claim",
            headers={
                "X-Komga-Email": admin.username,
                "X-Komga-Password": admin_password,
            },
        )
        admin.request("GET", "/api/v1/libraries")
    library_id = _library(admin, books, scan_interval)
    _reader(admin, library_id, reader_email, reader_password)

    audio = _Client(f"http://127.0.0.1:{audiobookshelf_port}")
    status = _object(audio.request("GET", "/status"))
    if status.get("isInit") is not True:
        message = "Audiobookshelf administrator is not initialized"
        raise RuntimeError(message)
    runtime = Path(os.environ.get("BOOKS_READY_DIR", "/run/homelab-books"))
    runtime.mkdir(mode=0o755, exist_ok=True)
    (runtime / "ready").touch(mode=0o644)


if __name__ == "__main__":
    _reconcile(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], sys.argv[4])
