"""Add Ollama's non-thinking setting to Stirling AI chat requests."""

import http.client
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import override

MAX_REQUEST_BYTES = 8 * 1024 * 1024
UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 11434


class Handler(BaseHTTPRequestHandler):
    """Forward chat requests while suppressing reasoning output and private logs."""

    @override
    def log_message(self, format: str, *_args: object) -> None:
        """Suppress request logging because document content is private."""
        # Requests may contain private document text. Do not log it.

    def do_POST(self) -> None:
        """Stream the bounded request through the loopback Ollama endpoint."""
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", ""))
            if length < 1 or length > MAX_REQUEST_BYTES:
                self.send_error(413)
                return
            request = json.loads(self.rfile.read(length))
            if not isinstance(request, dict):
                self.send_error(400)
                return
            request["reasoning_effort"] = "none"
            body = json.dumps(request, separators=(",", ":")).encode()
        except ValueError, UnicodeDecodeError, json.JSONDecodeError:
            self.send_error(400)
            return

        upstream = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=300)
        started_response = False
        try:
            upstream.request(
                "POST",
                self.path,
                body,
                {
                    "Content-Type": "application/json",
                    "Accept": "application/json, text/event-stream",
                },
            )
            response = upstream.getresponse()
            self.send_response(response.status)
            started_response = True
            content_type = response.getheader("Content-Type")
            if content_type:
                self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            while chunk := response.read1(16 * 1024):
                self.wfile.write(chunk)
                self.wfile.flush()
        except BrokenPipeError, ConnectionResetError:
            self.close_connection = True
        except OSError, http.client.HTTPException:
            if not started_response:
                self.send_error(502)
        finally:
            upstream.close()


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 11435), Handler).serve_forever()
