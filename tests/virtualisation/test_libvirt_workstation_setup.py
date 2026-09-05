"""Regression tests for libvirt workstation reconciliation."""

from __future__ import annotations

import base64
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SETUP_TEMPLATE = Path(
    os.environ.get(
        "LIBVIRT_WORKSTATION_SETUP_TEMPLATE",
        Path(__file__).parents[2]
        / "modules/nixos/virtualisation/scripts/libvirt-workstation-setup.sh.in",
    )
)
EXISTING_UUID = "70cb4ee0-a076-4ff6-a21c-b26f1a5c93d0"


class LibvirtWorkstationSetupTests(unittest.TestCase):
    """Exercise reconciliation against existing libvirt objects."""

    def test_existing_network_keeps_its_uuid_when_redefined(self) -> None:
        """Apply a changed definition without replacing network identity."""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            desired_network = root / "desired-network.xml"
            desired_network.write_text(
                "<network><name>dev-mgmt</name>"
                '<bridge name="virbr-mgmt" stp="on" delay="0"/>'
                "</network>\n",
                encoding="utf-8",
            )
            existing_network = root / "existing-network.xml"
            existing_network.write_text(
                "<network><name>dev-mgmt</name>"
                f"<uuid>{EXISTING_UUID}</uuid>"
                '<bridge name="old-bridge"/>'
                "</network>\n",
                encoding="utf-8",
            )
            defined_network = root / "defined-network.xml"

            network_manifest = root / "networks.tsv"
            network_manifest.write_text(
                f"dev-mgmt\tvirbr-mgmt\t192.168.123.0/24\t{desired_network}\n",
                encoding="utf-8",
            )
            guest_manifest = root / "guests.tsv"
            guest_manifest.write_text("", encoding="utf-8")

            pool_path = root / "pool"
            pool_definition = root / "pool.xml"
            pool_definition.write_text(
                f"<pool><name>workstation</name><target><path>{pool_path}</path>"
                "</target></pool>\n",
                encoding="utf-8",
            )

            fake_virsh = root / "virsh"
            fake_virsh.write_text(
                f"#!{shutil.which('bash')}\n"
                """set -euo pipefail
if [[ ${1-} == --connect ]]; then
    shift 2
fi
command_name=${1-}
shift
case "$command_name" in
    net-info)
        printf 'Active: yes\\n'
        ;;
    net-dumpxml)
        cat "$EXISTING_NETWORK"
        ;;
    net-uuid)
        printf '%s\\n' "$EXISTING_UUID"
        ;;
    net-define)
        cp "$1" "$DEFINED_NETWORK"
        if ! grep -Fq "<uuid>$EXISTING_UUID</uuid>" "$1"; then
            printf "error: operation failed: network 'dev-mgmt' already exists with uuid %s\\n" \
                "$EXISTING_UUID" >&2
            exit 1
        fi
        ;;
    net-autostart|pool-autostart|pool-refresh)
        ;;
    pool-info)
        printf 'State: running\\n'
        ;;
    pool-dumpxml)
        cat "$POOL_DEFINITION"
        ;;
    *)
        printf 'unexpected virsh command: %s\\n' "$command_name" >&2
        exit 2
        ;;
esac
""",
                encoding="utf-8",
            )
            fake_virsh.chmod(fake_virsh.stat().st_mode | stat.S_IXUSR)

            fake_xmllint = root / "xmllint"
            fake_xmllint.write_text(
                f"#!{shutil.which('bash')}\n"
                """if [[ $2 == 'string(/network/uuid)' ]]; then
    exit 0
fi
cat >/dev/null
printf '%s\\n' "$POOL_PATH"
""",
                encoding="utf-8",
            )
            fake_xmllint.chmod(fake_xmllint.stat().st_mode | stat.S_IXUSR)

            replacements = {
                "@bash@": shutil.which("bash") or "/bin/bash",
                "@guestManifest@": shlex.quote(str(guest_manifest)),
                "@grep@": shlex.quote(shutil.which("grep") or "grep"),
                "@libvirtUri@": shlex.quote("qemu:///system"),
                "@mktemp@": shlex.quote(shutil.which("mktemp") or "mktemp"),
                "@networkManifest@": shlex.quote(str(network_manifest)),
                "@perl@": shlex.quote(shutil.which("perl") or "perl"),
                "@poolDefinition@": shlex.quote(str(pool_definition)),
                "@poolName@": shlex.quote("workstation"),
                "@poolPath@": shlex.quote(str(pool_path)),
                "@rm@": shlex.quote(shutil.which("rm") or "rm"),
                "@virsh@": shlex.quote(str(fake_virsh)),
                "@xmllint@": shlex.quote(str(fake_xmllint)),
            }
            rendered = SETUP_TEMPLATE.read_text(encoding="utf-8")
            for token, value in replacements.items():
                rendered = rendered.replace(token, value)
            setup_script = root / "setup"
            setup_script.write_text(rendered, encoding="utf-8")
            setup_script.chmod(setup_script.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment.update({
                "DEFINED_NETWORK": str(defined_network),
                "EXISTING_NETWORK": str(existing_network),
                "EXISTING_UUID": EXISTING_UUID,
                "POOL_DEFINITION": str(pool_definition),
                "POOL_PATH": str(pool_path),
            })
            completed = subprocess.run(
                [setup_script],
                check=False,
                capture_output=True,
                env=environment,
                text=True,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn(
                f"<uuid>{EXISTING_UUID}</uuid>",
                defined_network.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'bridge name="virbr-mgmt"',
                defined_network.read_text(encoding="utf-8"),
            )


class WindowsVmControlTests(unittest.TestCase):
    """Exercise the privileged helper's text input and guest status boundaries."""

    @staticmethod
    def run_control(
        root: Path, command: str, *, input_text: str = "", status: str = ""
    ) -> subprocess.CompletedProcess[str]:
        """Run the real helper with fixed, temporary paths and a fake guest agent.

        Returns:
            The helper's exit status and captured output.

        """
        template = Path(
            os.environ.get(
                "LIBVIRT_WINDOWS_VM_CONTROL_TEMPLATE",
                Path(__file__).parents[2]
                / "modules/nixos/virtualisation/scripts/libvirt-windows-vm-control.sh.in",
            )
        )
        fake_virsh = root / "virsh"
        fake_virsh.write_text(
            f"#!{shutil.which('bash')}\n"
            'case "$3" in\n'
            "domid) printf '1\\n';;\n"
            "qemu-agent-command)\n"
            'case "${@: -1}" in\n'
            "*guest-file-open*) printf '{\"return\":1}';;\n"
            "*guest-file-read*) printf '%s' \"$GUEST_RESPONSE\";;\n"
            "*guest-file-close*) printf '{\"return\":{}}';;\n"
            "*) exit 2;; esac;;\n"
            "*) exit 2;; esac\n",
            encoding="utf-8",
        )
        fake_virsh.chmod(0o700)
        replacements = {
            token: shlex.quote(shutil.which(token) or ":")
            for token in re.findall(
                r"@([A-Za-z0-9]+)@", template.read_text(encoding="utf-8")
            )
        }
        replacements.update({
            "authorizedKeysFile": shlex.quote(str(root / "authorized_keys")),
            "chown": shlex.quote(shutil.which("true") or "true"),
            "guestName": "windows-runtime",
            "passwordFile": shlex.quote(str(root / "password")),
            "recipeFingerprint": "current-recipe",
            "runtimeDirectory": shlex.quote(str(root)),
            "stateDirectory": shlex.quote(str(root)),
            "virsh": shlex.quote(str(fake_virsh)),
        })
        script = root / "control"
        script.write_text(
            re.sub(
                r"@([A-Za-z0-9]+)@",
                lambda match: replacements[match[1]],
                template.read_text(encoding="utf-8"),
            ),
            encoding="utf-8",
        )
        script.chmod(0o700)
        return subprocess.run(
            [script, command, "windows-runtime"],
            input=input_text,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
            env={
                **os.environ,
                "GUEST_RESPONSE": json.dumps({
                    "return": {"buf-b64": base64.b64encode(status.encode()).decode()}
                }),
            },
        )

    def test_windows_baseline_accepts_crlf_and_lf(self) -> None:
        """A current PASS is recognized with either guest text line ending."""
        for newline in ("\n", "\r\n"):
            with (
                self.subTest(newline=repr(newline)),
                tempfile.TemporaryDirectory() as tmp,
            ):
                result = self.run_control(
                    Path(tmp),
                    "wait-baseline",
                    status=newline.join((
                        "state=PASS",
                        "fingerprint=current-recipe",
                        "",
                    )),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("state=PASS", result.stdout)

    def test_windows_baseline_rejects_stale_crlf_status(self) -> None:
        """CRLF normalization must retain the recipe fingerprint check."""
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_control(
                Path(tmp), "baseline", status="state=PASS\r\nfingerprint=old-recipe\r\n"
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale baseline", result.stderr)

    def test_windows_baseline_reports_crlf_failure(self) -> None:
        """A Windows FAIL returns its detail immediately instead of timing out."""
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_control(
                Path(tmp),
                "wait-baseline",
                status="state=FAIL\r\nfingerprint=current-recipe\r\ndetail=driver failed\r\n",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("driver failed", result.stderr)

    def test_unterminated_second_input_line_is_rejected(self) -> None:
        """Reject extra input before changing credentials or authorized keys."""
        for command in ("credential", "authorize"):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                result = self.run_control(
                    root, command, input_text="ExampleOnly123456\nextra"
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("exactly one line", result.stderr)
                self.assertFalse((root / "password").exists())
                self.assertFalse((root / "authorized_keys").exists())


if __name__ == "__main__":
    unittest.main()
