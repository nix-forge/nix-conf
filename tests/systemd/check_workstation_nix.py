"""Build and check dependent derivations through the installed bounded Nix helper."""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute only the supplied helper and installed Nix.
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

EXPECTED_ATTEMPTS = 2


def verify_root(nix: str, receipt: dict[str, Any], state: Path) -> None:
    """Require the private store's GC to recognize the retained logical root.

    Raises:
        AssertionError: The output is not protected by its retained root.

    """
    root = Path(receipt["receipt"]).parent / "result"
    logical = receipt["builds"][0]["outputs"]["out"]
    query = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Query the same trusted Nix installation.
        [
            str(Path(nix).resolve().with_name("nix-store")),
            "--store",
            "local?root=" + quote(str(state / "store"), safe="/"),
            "--query",
            "--roots",
            logical,
        ],
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    if str(root) not in query.stdout or str(root.readlink()) != logical:
        msg = "The private store does not recognize the retained output root"
        raise AssertionError(msg)


def main() -> None:
    """Verify real output roots, dependency checks and failed-attempt preservation.

    Raises:
        RuntimeError: A required native command is unavailable.
        AssertionError: A build, retained root or failed attempt violates the contract.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("helper", type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--memory-gib", type=int, default=4)
    args = parser.parse_args()
    state = args.state.resolve()
    state.mkdir(parents=True, mode=0o700, exist_ok=False)
    nix = shutil.which("nix")
    bash = shutil.which("bash")
    if not nix or not bash:
        msg = "Nix and Bash are required"
        raise RuntimeError(msg)
    bash_store = Path(bash).resolve().parent.parent
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Seed only the installed Bash closure.
        [
            nix,
            "--extra-experimental-features",
            "read-only-local-store",
            "copy",
            "--from",
            "local?read-only=true",
            "--to",
            "local?root=" + quote(str(state / "store"), safe="/"),
            str(bash_store),
        ],
        check=True,
    )
    expression = state / "proof.nix"
    expression.write_text(
        """let
    bash = (builtins.storePath BASH) + "/bin/bash";
    dependency = derivation {
        name = "bounded-proof-dependency";
        system = SYSTEM;
        builder = bash;
        args = [ "-euc" "printf 'bounded-proof\\n' > $out" ];
    };
in derivation {
    name = "bounded-proof-check";
    system = SYSTEM;
    builder = bash;
    input = dependency;
    args = [ "-euc" "read -r value < $input; test $value = bounded-proof; printf '%s\\n' $value > $out" ];
}
""".replace("BASH", json.dumps(str(bash_store))).replace(
            "SYSTEM",
            json.dumps(platform.machine() + "-linux"),
        ),
        encoding="utf-8",
    )
    command = [
        str(args.helper),
        "--memory-gib",
        str(args.memory_gib),
        "--state",
        str(state),
        "--impure",
        "--file",
        str(expression),
    ]
    result = subprocess.run(command, stdout=subprocess.PIPE, text=True, check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Public helper arguments, no shell.
    receipt = json.loads(result.stdout)
    outputs = receipt["physicalOutputs"]
    if (
        len(outputs) != 1
        or Path(outputs[0]).read_text(encoding="utf-8") != "bounded-proof\n"
    ):
        msg = "Dependency and check did not produce the expected real output"
        raise AssertionError(msg)
    verify_root(nix, receipt, state)
    failed = state / "failure.nix"
    failed.write_text(
        expression
        .read_text(encoding="utf-8")
        .replace(
            'name = "bounded-proof-check"',
            'name = "bounded-proof-failure"',
        )
        .replace("test $value = bounded-proof", "test $value = deliberately-wrong"),
        encoding="utf-8",
    )
    command[-1] = str(failed)
    result = subprocess.run(command, stdout=subprocess.PIPE, text=True, check=False)  # ruff: ignore[subprocess-without-shell-equals-true] - Verify the real failed package stays failed.
    failure = json.loads(result.stdout)
    if result.returncode == 0 or failure["status"] != "failed":
        msg = "A failed package was incorrectly accepted"
        raise AssertionError(msg)
    if len(list(state.glob("attempts/*/receipt.json"))) != EXPECTED_ATTEMPTS:
        msg = "The helper lost or replayed an attempt"
        raise AssertionError(msg)
    sys.stdout.write(
        json.dumps({
            "status": "passed",
            "receipt": receipt["receipt"],
            "failure": failure["receipt"],
        })
        + "\n"
    )


if __name__ == "__main__":
    main()
