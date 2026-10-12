"""Check the installed Actual server and its shipped web assets on loopback."""

import argparse
import json
import time
from html.parser import HTMLParser
from pathlib import Path
from typing import NoReturn, override
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen

_STARTUP_SECONDS = 30


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


class AssetParser(HTMLParser):
    """Find scripts and stylesheets that the shipped HTML requires."""

    def __init__(self) -> None:
        """Collect only executable scripts and stylesheet resources."""
        super().__init__()
        self.assets: list[str] = []

    @override
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        resource = values.get("src") if tag == "script" else values.get("href")
        if resource and (
            tag == "script" or (tag == "link" and values.get("rel") == "stylesheet")
        ):
            self.assets.append(resource)


def asset_paths(markup: str, root: Path) -> list[tuple[str, Path]]:
    """Resolve only local shipped resources, rejecting empty or escaping HTML.

    Returns:
        Required asset URLs and their installed files.

    """
    parser = AssetParser()
    parser.feed(markup)
    if not parser.assets:
        message = "The shipped page has no executable or stylesheet resources"
        _reject(message)
    assets = []
    for url in parser.assets:
        parsed = urlsplit(url)
        if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
            message = "The packaged page must refer to plain local assets"
            _reject(message)
        path = (root / unquote(parsed.path).lstrip("/")).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            message = "A required shipped asset is absent or outside webRoot"
            _reject(message)
        assets.append((url, path))
    return assets


def get(port: int, path: str) -> bytes:
    """Fetch only the isolated server's loopback endpoint.

    Returns:
        The served bytes, with HTTP failures propagated.

    """
    url = f"http://127.0.0.1:{port}/{path.lstrip('/')}"
    with urlopen(url, timeout=2) as response:
        return response.read()


def _wait_health(port: int) -> object:
    deadline = time.monotonic() + _STARTUP_SECONDS
    while True:
        try:
            health = json.loads(get(port, "health"))
            break
        except HTTPError:
            raise
        except URLError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.1)
    return health


def verify(port: int, root: Path, version: str) -> None:
    """Verify service identity, SQLite readiness and installed asset bytes."""
    health = _wait_health(port)
    if health != {"status": "UP"}:
        message = "Unexpected Actual health response"
        _reject(message)
    info = json.loads(get(port, "info"))
    if (
        info["build"]["version"] != version
        or info["build"]["name"] != "@actual-app/sync-server"
    ):
        message = "The running service is not the expected installed Actual package"
        _reject(message)
    account = json.loads(get(port, "account/needs-bootstrap"))
    if account["status"] != "ok" or account["data"]["bootstrapped"] is not False:
        message = (
            "The fresh server did not open and migrate its account SQLite database"
        )
        _reject(message)
    html = get(port, "")
    if html != (root / "index.html").read_bytes():
        message = "The server did not serve its installed web root"
        _reject(message)
    for url, file in asset_paths(html.decode(), root):
        if get(port, url) != file.read_bytes():
            message = "A served asset differs from the installed package"
            _reject(message)


def main() -> None:
    """Validate the bounded native service proof supplied by Nix."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", type=int)
    parser.add_argument("root", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()
    verify(args.port, args.root, args.version)
    print("Verified installed Actual service, SQLite readiness and web assets")  # ruff: ignore[print] - Report native runtime proof to CI.


if __name__ == "__main__":
    main()
