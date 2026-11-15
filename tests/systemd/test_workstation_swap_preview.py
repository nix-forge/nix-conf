"""Require managed unit ownership before retiring a scoped swap preview."""

import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Fixed local activation fixture.
import tempfile
import unittest
from pathlib import Path

SOURCE = (
    Path(__file__).parents[2]
    / "homes/desktop/local/codex-resources/scripts/retire-swap-preview.sh"
)
RELATIVE = ".config/systemd/user/app-codex.slice"
BASH = shutil.which("bash")


class SwapPreviewTests(unittest.TestCase):
    """Exercise the activation boundary with disposable generation links."""

    def test_only_managed_generation_retires_preview(self) -> None:
        """Failed, missing and foreign installation must keep the preview root."""
        bash = BASH
        if bash is None:
            self.fail("Bash is required to execute the activation fixture")
        for state in ("preview", "managed", "missing", "dangling", "no-generation"):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                generation = work / "generation"
                expected = generation / "home-files" / RELATIVE
                expected.parent.mkdir(parents=True)
                managed = work / "managed-unit"
                managed.write_text("managed\n")
                expected.symlink_to(managed)
                preview = work / "preview-unit"
                preview.write_text("preview\n")
                unit = work / "installed-unit"
                unit.symlink_to(managed if state == "managed" else preview)
                if state == "missing":
                    expected.unlink()
                if state == "dangling":
                    managed.unlink()
                stamp = work / "retired"
                environment = os.environ | {"newGenPath": str(generation)}
                if state == "no-generation":
                    environment.pop("newGenPath")
                subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed script; paths passed as literal arguments.
                    [
                        bash,
                        "-c",
                        (
                            "fixture_stamp=$4; "
                            'nixProfileRemove() { printf "%s" "$1" > "$fixture_stamp"; }; '
                            'source "$1" "$2" "$3"'
                        ),
                        "swap-preview-fixture",
                        str(SOURCE),
                        str(unit),
                        RELATIVE,
                        str(stamp),
                    ],
                    env=environment,
                    check=True,
                    capture_output=True,
                )
                if state == "managed":
                    self.assertEqual(stamp.read_text(), "workstation-swap-preview")
                else:
                    self.assertFalse(stamp.exists())


if __name__ == "__main__":
    unittest.main()
