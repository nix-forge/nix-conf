"""Exercise the Windows ISO acquisition boundary without downloading media."""

from __future__ import annotations

import hashlib
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TEMPLATE = (
    Path(__file__).parents[2] / "modules/nixos/virtualisation/scripts/windows-vm.sh.in"
)
ISO_NAME = "Win11_25H2_English_x64_v2.iso"


def _shell_fixture(name: str, replacements: dict[str, str]) -> str:
    """Load a Bash fixture without recursively replacing inserted values.

    Returns:
        The fixture with its runtime executable and path substitutions.

    """
    source = (Path(__file__).with_name("fixtures") / name).read_text(encoding="utf-8")
    return re.sub(r"@(__value[0-9]+)@", lambda match: replacements[match[1]], source)


def render_cli(root: Path, iso_hash: str) -> Path:
    """Render the CLI template with isolated media and command fixtures.

    Returns:
        The rendered command path.

    """
    media = root / "boot"
    media.mkdir()
    destination = media / ISO_NAME
    resolver = root / "msdl"
    resolver.write_text(
        f"#!{shutil.which('bash')}\n"
        'printf "%s|%s|%s\\n" "$MSDL_NO_TELEMETRY" '
        '"$MSDL_NO_CONTRIBUTE" "$*" > "$RESOLVER_LOG"\n'
        'printf "%s\\n" "$RESOLVED_URL"\n',
        encoding="utf-8",
    )
    resolver.chmod(0o700)
    downloader = root / "curl"
    downloader.write_text(
        _shell_fixture(
            "curl-iso-download.sh.in", {"__value0": str(shutil.which("bash"))}
        ),
        encoding="utf-8",
    )
    downloader.chmod(0o700)
    replacements = {
        "bash": str(shutil.which("bash")),
        "cat": str(shutil.which("cat")),
        "chmod": str(shutil.which("chmod")),
        "curl": str(downloader),
        "guestName": "fixture",
        "install": str(shutil.which("install")),
        "isoLanguage": "English",
        "isoPath": shlex.quote(str(destination)),
        "isoProductId": "3321",
        "isoSha256": iso_hash,
        "isoSha256Path": shlex.quote(str(destination) + ".sha256"),
        "mktemp": str(shutil.which("mktemp")),
        "msdl": str(resolver),
        "mv": str(shutil.which("mv")),
        "privilegedControl": str(shutil.which("true")),
        "rm": str(shutil.which("rm")),
        "setupWizard": str(shutil.which("true")),
        "sha256sum": str(shutil.which("sha256sum")),
        "sshKeygen": str(shutil.which("true")),
        "sudo": str(shutil.which("true")),
    }
    rendered = TEMPLATE.read_text(encoding="utf-8")
    for key, value in replacements.items():
        rendered = rendered.replace(f"@{key}@", value)
    assert re.search(r"@[A-Za-z]+@", rendered) is None
    script = root / "windows-vm"
    script.write_text(rendered, encoding="utf-8")
    script.chmod(0o700)
    return script


CASES = [
    (
        f"https://software.download.prss.microsoft.com/db/{ISO_NAME}?expires=tomorrow",
        True,
        True,
    ),
    (f"https://attacker.example/db/{ISO_NAME}", True, False),
    ("https://software.download.prss.microsoft.com/db/wrong.iso", True, False),
    (
        f"https://software.download.prss.microsoft.com/db/{ISO_NAME}",
        False,
        False,
    ),
]


class WindowsIsoFetchTests(unittest.TestCase):
    """Check the link and byte boundary before installer media is staged."""

    def test_fetch_iso_requires_microsoft_url_filename_and_hash(self) -> None:
        """Unexpected links or bytes cannot become the installer ISO."""
        for url, correct_hash, should_stage in CASES:
            with (
                self.subTest(url=url, correct_hash=correct_hash),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = Path(directory)
                fixture = root / "sample.iso"
                fixture.write_bytes(b"fixture Windows ISO bytes")
                expected_hash = hashlib.sha256(fixture.read_bytes()).hexdigest()
                if not correct_hash:
                    expected_hash = "0" * 64
                script = render_cli(root, expected_hash)
                resolver_log = root / "resolver.log"
                download_log = root / "download.log"
                result = subprocess.run(
                    [str(script), "fetch-iso"],
                    capture_output=True,
                    check=False,
                    text=True,
                    env={
                        **os.environ,
                        "RESOLVED_URL": url,
                        "RESOLVER_LOG": str(resolver_log),
                        "DOWNLOAD_LOG": str(download_log),
                        "ISO_FIXTURE": str(fixture),
                    },
                )
                destination = root / "boot" / ISO_NAME
                self.assertEqual(result.returncode == 0, should_stage, result.stderr)
                self.assertEqual(destination.exists(), should_stage)
                self.assertEqual(
                    download_log.exists(),
                    "attacker.example" not in url and "wrong.iso" not in url,
                )
                self.assertEqual(
                    resolver_log.read_text(encoding="utf-8").strip(),
                    "1|1|--id 3321 --lang English --no-contribute",
                )


if __name__ == "__main__":
    unittest.main()
