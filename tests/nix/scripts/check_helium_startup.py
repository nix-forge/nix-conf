"""Exercise the Nix-generated startup hooks, including an empty flag list."""

import json
import os
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute the generated fixture wrapper.
import sys
import tempfile
from pathlib import Path


def main() -> None:
    """Run both packaged launchers with the actual Nix-generated policy."""
    install = Path(sys.argv[1]).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        # Relocate only the configured fixture directory into the build sandbox.
        # Keep the actual generated policy, writer and wrapper construction.
        for hook in set(re.findall(r"source (/nix/store/[^; '\n]+)", install)):
            source = Path(hook)
            relocated = root / source.name
            relocated.write_text(
                source.read_text(encoding="utf-8").replace(
                    str(Path(sys.argv[3]).parent), directory
                ),
                encoding="utf-8",
            )
            install = install.replace(hook, str(relocated))
        assert "source " in install, "empty flags must retain startup hooks"
        output = root / "package"
        executable = output / "Applications/Helium.app/Contents/MacOS/Helium"
        executable.parent.mkdir(parents=True)
        (output / "bin").mkdir()
        executable.write_bytes(Path(sys.argv[2]).read_bytes())
        executable.chmod(0o755)
        preferences = root / "Default/Preferences"
        preferences.parent.mkdir()
        preferences.write_text(
            json.dumps({"obsolete": True, "unmanaged": 42}), encoding="utf-8"
        )
        script = root / "install.sh"
        script.write_text(install, encoding="utf-8")
        environment = os.environ | {
            "out": str(output),
            "BASH_ENV": os.environ["BUILD_SETUP"],
        }
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Declared executable and generated fixture arguments.
            [os.environ["BASH_PROGRAM"], "-e", str(script)], env=environment, check=True
        )
        for launcher in [executable, output / "bin/helium"]:
            result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Generated fixture executable, no shell input.
                [str(launcher)], check=False, capture_output=True, text=True
            )
            assert result.returncode == 0, (
                result.returncode,
                result.stdout,
                result.stderr,
            )
            assert result.stdout == "browser reached\n", result
            assert not result.stderr, result
            value = json.loads(preferences.read_text(encoding="utf-8"))
            assert value["helium"]["browser"]["layout"] == 7, value
            assert value["unmanaged"] == 42, value
            assert "obsolete" not in value, value


if __name__ == "__main__":
    main()
