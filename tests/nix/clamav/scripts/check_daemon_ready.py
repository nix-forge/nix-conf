"""Require a real ClamAV response within one blocking protocol deadline."""

import socket
import sys
import time

RESPONSE_LIMIT = 32
TIMEOUT_MESSAGE = "ClamAV readiness deadline expired"
CLOSED_MESSAGE = "ClamAV closed the readiness connection"
OVERSIZE_MESSAGE = "ClamAV readiness response exceeds its limit"


def check_ready(endpoint: str, budget_seconds: float) -> None:
    """Connect once and wait for PONG, including daemon initialization.

    Raises:
        RuntimeError: The daemon closes the connection or returns an invalid reply.

    """
    deadline = time.monotonic() + budget_seconds

    def remaining() -> float:
        """Bound every operation by the same deadline.

        Returns:
            The remaining deadline budget in seconds.

        Raises:
            TimeoutError: The overall readiness deadline expired.

        """
        value = deadline - time.monotonic()
        if value <= 0:
            raise TimeoutError(TIMEOUT_MESSAGE)
        return value

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(remaining())
        client.connect(endpoint)
        client.settimeout(remaining())
        client.sendall(b"zPING\0")
        response = bytearray()
        while b"\0" not in response:
            client.settimeout(remaining())
            chunk = client.recv(RESPONSE_LIMIT - len(response))
            if not chunk:
                raise RuntimeError(CLOSED_MESSAGE)
            response.extend(chunk)
            if len(response) >= RESPONSE_LIMIT:
                raise RuntimeError(OVERSIZE_MESSAGE)
        if response != b"PONG\0":
            message = f"Unexpected ClamAV readiness response: {response!r}"
            raise RuntimeError(message)


if __name__ == "__main__":
    check_ready(sys.argv[1], float(sys.argv[2]))
