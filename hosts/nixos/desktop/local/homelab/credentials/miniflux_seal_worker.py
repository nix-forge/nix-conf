"""Seal one credential request received through SSH stdin."""

import base64
import json
import subprocess
import sys
import tempfile
from pathlib import Path


def handle_request() -> None:
    """Execute one request using private temporary files and sanitized output."""
    request = json.load(sys.stdin)
    with tempfile.TemporaryDirectory(prefix="miniflux-seal-") as temporary:
        root = Path(temporary)
        plan = root / "plan.json"
        plan.write_text(json.dumps(request["plan"]))
        source = Path(request["source"])
        if source.is_absolute() or ".." in source.parts:
            raise ValueError("unsafe source path")
        target = root / source
        target.parent.mkdir(parents=True)
        operation = request["operation"]
        if operation == "compare":
            target.write_bytes(base64.b64decode(request["ciphertext"], validate=True))
            argv = [
                "nix-seal",
                "secret",
                "reveal",
                "--plan",
                str(plan),
                "--repository-root",
                str(root),
                "--secret",
                request["secret"],
                "--identity",
                request["identity"],
            ]
        elif operation == "create":
            argv = [
                "nix-seal",
                "secret",
                "bootstrap",
                "complete",
                "--bootstrap-plan",
                str(plan),
                "--repository-root",
                str(root),
                "--secret",
                request["secret"],
                "--authorizer-key",
                request["authorizer_key"],
            ]
        else:
            raise ValueError("unsupported operation")
        result = subprocess.run(
            argv, input=request["value"], text=True, capture_output=True, check=False
        )
        if result.returncode:
            raise RuntimeError("nix-seal rejected the remote request")
        if operation == "compare":
            same = result.stdout == request["value"]
            sys.stdout.write("match" if same else "mismatch")
        else:
            sys.stdout.write(base64.b64encode(target.read_bytes()).decode())


if __name__ == "__main__":
    try:
        handle_request()
    except OSError, KeyError, RuntimeError, ValueError:
        print(
            "remote nix-seal operation failed; secret output suppressed",
            file=sys.stderr,
        )
        sys.exit(1)
