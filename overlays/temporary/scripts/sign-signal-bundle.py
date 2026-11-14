"""Seal the final Nix Electron bundle with upstream, explicitly scoped entitlements."""

import argparse
import plistlib
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import tempfile
from pathlib import Path


def sign(bundle: Path, upstream: Path) -> None:
    """Preserve upstream entitlement sets and isolate grants to executable scopes.

    Raises:
        ValueError: The helper layout differs from the reviewed Electron layout.

    """
    helpers = sorted((bundle / "Contents/Frameworks").glob("*.app"))
    expected = {
        "Signal Helper.app",
        "Signal Helper (GPU).app",
        "Signal Helper (Plugin).app",
        "Signal Helper (Renderer).app",
    }
    if {helper.name for helper in helpers} != expected:
        message = "Signal helper layout changed; review signing scopes"
        raise ValueError(message)

    with tempfile.TemporaryDirectory(prefix="signal-entitlements-") as directory:
        plists = []
        for name in ("entitlements.mac.plist", "entitlements.mac.inherit.plist"):
            raw = (upstream / name).read_bytes()
            # Upstream places copyright comments before its XML declaration.
            # Normalize that preamble before plistlib's format detection.
            entitlements = plistlib.loads(raw[raw.index(b"<?xml") :])
            # Nix's ad hoc code has no shared vendor Team ID. Hardened runtime
            # otherwise rejects the embedded Electron framework and native modules.
            # Keep every upstream entitlement; add only this necessary exception.
            entitlements["com.apple.security.cs.disable-library-validation"] = True
            destination = Path(directory) / name
            with destination.open("wb") as output:
                plistlib.dump(entitlements, output)
            plists.append(destination)

        command = [
            "rcodesign",
            "sign",
            "--config-file",
            "/dev/null",
            "--code-signature-flags",
            "runtime",
            "--entitlements-xml-file",
            str(plists[0]),
        ]
        for helper in helpers:
            scope = helper.relative_to(bundle).as_posix()
            command.extend([
                "--code-signature-flags",
                f"{scope}:runtime",
                "--entitlements-xml-file",
                f"{scope}:{plists[1]}",
            ])
        command.append(str(bundle))
        # Executable and argument layout are fixed; no shell evaluates paths.
        subprocess.run(command, check=True)  # ruff: ignore[subprocess-without-shell-equals-true]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("upstream_build", type=Path)
    arguments = parser.parse_args()
    sign(arguments.bundle, arguments.upstream_build)
