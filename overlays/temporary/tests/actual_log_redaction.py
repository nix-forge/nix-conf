"""Probe installed Actual log privacy with synthetic values on loopback only."""

# ruff: file-ignore[magic-value-comparison] -- Exact HTTP statuses and protocol strings are independent test expectations.
import argparse
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

# These are public synthetic canaries, never credentials for a real service.
_CANARIES = {
    "code": "canary-actual-code-7f598c",
    "state": "canary-actual-state-7f598c",
    "token": "canary-actual-token-7f598c",
}
_SECRET = "canary-actual-secret-value-7f598c"
_ERROR = "canary-actual-provider-error-7f598c"
_PASSWORD = "canary-actual-password-7f598c"


def request(
    port: int, path: str, payload: dict[str, str] | None = None, token: str = ""
) -> tuple[int, bytes]:
    """Call the isolated packaged server and return its status and body."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Actual-Token"] = token
    body = None if payload is None else json.dumps(payload).encode()
    query = urlencode(_CANARIES)
    req = Request(f"http://127.0.0.1:{port}/{path}?{query}", data=body, headers=headers)
    with urlopen(req, timeout=10) as response:
        return response.status, response.read()


def expect_ok(response: tuple[int, bytes]) -> dict[str, object]:
    """Require a completed successful API operation, not a skipped error path."""
    status, body = response
    parsed = json.loads(body)
    if not isinstance(parsed, dict) or status != 200 or parsed.get("status") != "ok":
        message = "Installed Actual rejected the synthetic privacy fixture"
        raise ValueError(message)
    return parsed


def probe(port: int) -> None:
    """Exercise real request logging, persisted secrets and a local bank error."""
    expect_ok(request(port, "account/bootstrap", {"password": _PASSWORD}))
    login = expect_ok(request(port, "account/login", {"password": _PASSWORD}))
    data = login["data"]
    if not isinstance(data, dict):
        message = "Installed Actual did not return login data"
        raise ValueError(message)
    token = data.get("token")
    if not isinstance(token, str):
        message = "Installed Actual did not return an authenticated session"
        raise ValueError(message)
    expect_ok(
        request(port, "secret/", {"name": "simplefin_token", "value": _SECRET}, token)
    )
    status, _ = request(port, "secret/simplefin_token", token=token)
    if status != 204:
        message = "Synthetic secret did not persist through the installed API"
        raise ValueError(message)
    # The reviewed route rejects '/' before calling any external bank service.
    result = expect_ok(
        request(
            port,
            "gocardless/create-web-token",
            {"institutionId": "invalid/" + _ERROR},
            token,
        )
    )
    details = result.get("data")
    if not isinstance(details, dict) or details.get("error_code") != "INTERNAL_ERROR":
        message = "Installed bank error handler was not exercised"
        raise ValueError(message)
    if _ERROR not in str(details.get("error_type")):
        message = "Expected synthetic provider error was not returned to the client"
        raise ValueError(message)


def verify(log: Path) -> None:
    """Inspect fully drained real stdout/stderr, with useful-path positive controls."""
    text = log.read_text()
    for canary in [*_CANARIES.values(), _SECRET, _ERROR, _PASSWORD]:
        if canary in text:
            message = "Installed Actual leaked a synthetic secret into ordinary logs"
            raise ValueError(message)
    for evidence in [
        "setting secret 'simplefin_token'",
        "/secret",
        "/gocardless/create-web-token",
        "Error",
    ]:
        if evidence not in text:
            message = "The log privacy proof did not observe all expected logging paths"
            raise ValueError(message)
    if "actual-sensitive:" in text:
        message = "Sensitive debug channels unexpectedly produced output"
        raise ValueError(message)


def main() -> None:
    """Run probes while the service lives, then verify logs after its scope drains."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("probe").add_argument("port", type=int)
    commands.add_parser("verify").add_argument("log", type=Path)
    args = parser.parse_args()
    if args.command == "probe":
        probe(args.port)
    else:
        verify(args.log)


if __name__ == "__main__":
    main()
