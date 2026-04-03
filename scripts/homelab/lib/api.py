from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ApiClient:
    base_url: str
    default_headers: dict[str, str]

    def _url(self, path: str) -> str:
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return urllib.parse.urljoin(self.base_url.rstrip("/") + "/", path.lstrip("/"))

    def request(
        self,
        method: str,
        path: str,
        *,
        expected: set[int] | None = None,
        json_body: Any | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, Any]:
        req_headers = dict(self.default_headers)
        if headers:
            req_headers.update(headers)

        data: bytes | None = None
        if json_body is not None:
            data = json.dumps(json_body).encode("utf-8")
            req_headers.setdefault("Content-Type", "application/json")

        req = urllib.request.Request(
            self._url(path),
            method=method,
            headers=req_headers,
            data=data,
        )

        try:
            with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310
                status = resp.getcode()
                body = resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            status = exc.code
            body = exc.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as exc:
            raise RuntimeError(
                f"request failed: {method} {self._url(path)}: {exc}"
            ) from exc

        if expected is None:
            expected = {200}
        if status not in expected:
            raise RuntimeError(
                f"unexpected status {status} for {method} {self._url(path)}; body={body[:500]}"
            )

        if not body.strip():
            return status, None

        try:
            return status, json.loads(body)
        except json.JSONDecodeError:
            return status, body
