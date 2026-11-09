"""Exercise the chat proxy with real HTTP response parsing and no live service."""

from __future__ import annotations

import http.client
import importlib.util
import io
import json
import socket
from contextlib import contextmanager
from http import HTTPStatus
from pathlib import Path
from typing import TYPE_CHECKING
from unittest.mock import Mock, patch

import pytest

if TYPE_CHECKING:
    from collections.abc import Generator

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "ollama_chat_proxy",
    ROOT / "hosts/nixos/desktop/local/homelab/stirling-pdf/ollama_chat_proxy.py",
)
assert SPEC is not None
assert SPEC.loader is not None
proxy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(proxy)


def parsed_response(raw: bytes) -> http.client.HTTPResponse:
    """Parse a raw fixture using the upstream HTTP parser.

    Returns:
        An open response that the caller must close.

    """
    sock = Mock(spec=socket.socket)
    sock.makefile.return_value = io.BytesIO(raw)
    response = http.client.HTTPResponse(sock)
    response.begin()
    return response


@contextmanager
def exchange(
    headers: bytes,
    body: bytes = b"private upstream body",
    status: int = 200,
) -> Generator[tuple[http.client.HTTPResponse, Mock, Mock]]:
    """Run the production handler against one parsed upstream fixture.

    Yields:
        The downstream response, write spy, and closed upstream connection.

    """
    response = parsed_response(
        f"HTTP/1.1 {status} Fixture\r\nContent-Length: {len(body)}\r\n".encode()
        + headers
        + b"\r\n"
        + body
    )
    connection = Mock()
    connection.getresponse.return_value = response
    connection.close.side_effect = response.close
    handler = proxy.Handler.__new__(proxy.Handler)
    request = json.dumps({
        "model": "fixture-model",
        "stream": True,
        "messages": ["private document"],
    }).encode()
    handler.path = "/v1/chat/completions"
    handler.command = "POST"
    handler.requestline = "POST /v1/chat/completions HTTP/1.1"
    handler.request_version = "HTTP/1.1"
    handler.headers = http.client.parse_headers(
        io.BytesIO(f"Content-Length: {len(request)}\r\n\r\n".encode())
    )
    handler.rfile = io.BytesIO(request)
    output = io.BytesIO()
    writer = Mock(wraps=output)
    handler.wfile = writer
    with patch.object(
        proxy.http.client, "HTTPConnection", return_value=connection
    ) as factory:
        handler.do_POST()
    factory.assert_called_once_with("127.0.0.1", 11434, timeout=300)
    connection.close.assert_called_once()
    assert response.isclosed()
    forwarded = json.loads(connection.request.call_args.args[2])
    assert forwarded == {
        "model": "fixture-model",
        "stream": True,
        "messages": ["private document"],
        "reasoning_effort": "none",
    }
    reply = parsed_response(output.getvalue())
    try:
        yield reply, writer, connection
    finally:
        reply.close()


@pytest.mark.parametrize(
    "header",
    [
        b"Content-Type: application/json\r\n folded-value\r\n",
        b"Content-Type: text/event-stream\n\tfolded-value\r\n",
        b"Content-Type: application/json\r folded-value\r\n",
    ],
)
def test_rejects_parsed_header_line_breaks(
    header: bytes, capsys: pytest.CaptureFixture
) -> None:
    """Reject parsed line breaks without sending upstream content or logs."""
    # Real HTTPResponse parsing preserves obsolete continuation whitespace.
    with exchange(header) as (reply, _, _):
        assert reply.status == HTTPStatus.BAD_GATEWAY
        assert b"private upstream body" not in reply.read()
        assert "folded-value" not in str(reply.headers)
    captured = capsys.readouterr()
    assert not captured.out
    assert not captured.err


@pytest.mark.parametrize(
    ("content_type", "status"),
    [
        (b"application/json", 200),
        (b'application/json; charset="utf-8"', 200),
        (b"text/event-stream; charset=utf-8", 200),
        (b"text/event-stream;\tcharset=utf-8", 200),
        (b"text/plain; charset=utf-8", 400),
        (None, 200),
    ],
)
def test_preserves_valid_upstream_responses(
    content_type: bytes | None, status: int, capsys: pytest.CaptureFixture
) -> None:
    """Preserve valid media types, error responses, missing types, and privacy."""
    headers = (
        b"" if content_type is None else b"Content-Type: " + content_type + b"\r\n"
    )
    with exchange(headers, status=status) as (reply, _, _):
        assert reply.status == status
        assert reply.getheader("Content-Type") == (
            None if content_type is None else content_type.decode()
        )
        assert reply.getheader("Cache-Control") == "no-store"
        assert reply.read() == b"private upstream body"
    captured = capsys.readouterr()
    assert not captured.out
    assert not captured.err


def test_streams_body_in_bounded_flushed_chunks() -> None:
    """Retain incremental streaming without buffering or changing body bytes."""
    body = b"data: fixture\n\n" * 4000
    with exchange(b"Content-Type: text/event-stream\r\n", body=body) as (
        reply,
        writer,
        _,
    ):
        assert reply.read() == body
        chunks = [call.args[0] for call in writer.write.call_args_list[1:]]
        assert len(chunks) > 1
        assert b"".join(chunks) == body
        assert max(map(len, chunks)) <= 16 * 1024
        assert writer.flush.call_count == len(chunks)
