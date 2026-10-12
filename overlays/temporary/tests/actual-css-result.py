"""Accept only a failed native build with an Actual theme CSS resolver error."""

import argparse
import re
from pathlib import Path
from typing import NoReturn


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


_ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
_RESOLVER = re.compile(
    r"could not (?:load|resolve)|failed to resolve|cannot resolve|failed to load",
    re.IGNORECASE,
)
_THEMES = {"dark", "light", "midnight", "palette", "sidebar-redesign-light"}
_NATIVE_ERRORS = (
    "ERR_DLOPEN_FAILED",
    "NODE_MODULE_VERSION",
    "Could not locate the bindings file",
    "gyp ERR!",
    "ERR_MODULE_NOT_FOUND",
)


def verify(log: str, status: int, mode: str) -> None:
    """Require the specific upstream import failure, with no native Node error."""
    if status != 1:
        message = "Expected a normal failed build, not success or a signal"
        _reject(message)
    log = _ANSI.sub("", log)
    if any(marker in log for marker in _NATIVE_ERRORS):
        message = "A Node or native-addon failure cannot establish the CSS regression"
        _reject(message)
    names = {"sidebar-redesign-light"} if mode == "four" else _THEMES
    lines = log.splitlines()
    for index, line in enumerate(lines):
        if not _RESOLVER.search(line):
            continue
        context = "\n".join(lines[max(0, index - 2) : index + 6])
        if "desktop-client/src/style/theme.tsx" not in context:
            continue
        if any(f"themes/{name}.css" in context for name in names):
            return
    message = "No exact Actual theme import/resolver failure was found"
    _reject(message)


def main() -> None:
    """Classify the captured native build log."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["raw", "four"])
    parser.add_argument("status", type=int)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    verify(args.log.read_text(), args.status, args.mode)
    print(f"Verified Actual CSS resolver failure: {args.mode}")  # ruff: ignore[print] - Report native classification to CI.


if __name__ == "__main__":
    main()
