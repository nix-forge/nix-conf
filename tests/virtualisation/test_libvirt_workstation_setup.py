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
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest
from notification_process import run as run_command

SETUP_TEMPLATE = Path(
    os.environ.get(
        "LIBVIRT_WORKSTATION_SETUP_TEMPLATE",
        Path(__file__).parents[2]
        / "modules/nixos/virtualisation/scripts/libvirt-workstation-setup.sh.in",
    )
)


def _shell_fixture(name: str, replacements: dict[str, str]) -> str:
    """Load a Bash fixture without recursively replacing inserted values.

    Returns:
        The fixture with its runtime executable and path substitutions.

    """
    source = (Path(__file__).with_name("fixtures") / name).read_text(encoding="utf-8")
    return re.sub(r"@(__value[0-9]+)@", lambda match: replacements[match[1]], source)


def required_command(name: str) -> str:
    """Return a fixture dependency, failing clearly if the test shell lacks it.

    Returns:
        The absolute executable path.

    Raises:
        RuntimeError: A required test dependency is unavailable.

    """
    command = shutil.which(name)
    if command is None:
        message = f"Missing test dependency {name}; use just test-python"
        raise RuntimeError(message)
    return command


EXISTING_UUID = "70cb4ee0-a076-4ff6-a21c-b26f1a5c93d0"


class LibvirtWorkstationSetupTests(unittest.TestCase):
    """Exercise reconciliation against existing libvirt objects."""

    def test_existing_network_and_pool_keep_their_uuids(self) -> None:
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
                '<pool><name>workstation</name><features><cow state="yes"/></features>'
                f"<target><path>{pool_path}</path>"
                "</target></pool>\n",
                encoding="utf-8",
            )

            fake_virsh = root / "virsh"
            fake_virsh.write_text(
                _shell_fixture(
                    "virsh-existing-network-pool.sh.in",
                    {"__value0": str(required_command("bash"))},
                ),
                encoding="utf-8",
            )
            fake_virsh.chmod(fake_virsh.stat().st_mode | stat.S_IXUSR)

            replacements = {
                "@bash@": required_command("bash"),
                "@guestManifest@": shlex.quote(str(guest_manifest)),
                "@grep@": shlex.quote(required_command("grep")),
                "@libvirtUri@": shlex.quote("qemu:///system"),
                "@mktemp@": shlex.quote(required_command("mktemp")),
                "@networkManifest@": shlex.quote(str(network_manifest)),
                "@python@": shlex.quote(sys.executable),
                "@xmlHelper@": shlex.quote(
                    str(SETUP_TEMPLATE.parent / "libvirt_xml.py")
                ),
                "@poolDefinition@": shlex.quote(str(pool_definition)),
                "@poolName@": shlex.quote("workstation"),
                "@poolPath@": shlex.quote(str(pool_path)),
                "@rm@": shlex.quote(required_command("rm")),
                "@virsh@": shlex.quote(str(fake_virsh)),
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
                "DEFINED_POOL": str(root / "defined-pool.xml"),
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
            self.assertIn(
                f"<uuid>{EXISTING_UUID}</uuid>",
                (root / "defined-pool.xml").read_text(encoding="utf-8"),
            )
            cow = ET.fromstring(
                (root / "defined-pool.xml").read_text(encoding="utf-8")
            ).find("./features/cow")
            self.assertIsNotNone(cow)
            assert cow is not None
            self.assertEqual(cow.get("state"), "yes")


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
            _shell_fixture(
                "virsh-guest-file-response.sh.in",
                {"__value0": str(required_command("bash"))},
            ),
            encoding="utf-8",
        )
        fake_virsh.chmod(0o700)
        unexpected = root / "unexpected-command"
        unexpected.write_text(
            f"#!{required_command('bash')}\n"
            "printf 'unexpected installer command in status/input test\\n' >&2\n"
            "exit 99\n",
            encoding="utf-8",
        )
        unexpected.chmod(0o700)
        replacements = {
            "authorizedKeysFile": shlex.quote(str(root / "authorized_keys")),
            "python": shlex.quote(sys.executable),
            "xmlHelper": shlex.quote(str(SETUP_TEMPLATE.parent / "libvirt_xml.py")),
            "chown": shlex.quote(required_command("true")),
            "guestName": "windows-runtime",
            "guestUuid": EXISTING_UUID,
            "libvirtUri": "qemu:///fixture",
            "autostart": "false",
            "diskSizeGiB": "1",
            "diskSerial": "fixture-disk",
            "imageName": "fixture-image",
            "release": "fixture-release",
            "isoSha256": "0" * 64,
            "downloadPage": "https://example.invalid/installer",
            "qemuUser": "fixture",
            "qemuGroup": "fixture",
            "mediaInspectorUser": "fixture",
            "mediaInspectorGroup": "fixture",
            "passwordFile": shlex.quote(str(root / "password")),
            "recipeFingerprint": "current-recipe",
            "runtimeDirectory": shlex.quote(str(root)),
            "stateDirectory": shlex.quote(str(root)),
            "virsh": shlex.quote(str(fake_virsh)),
        }
        # These commands must never run during input validation or status reads.
        # A failing sentinel catches an accidental installer/privilege operation.
        for token in (
            "fuseArchive",
            "mountpoint",
            "primeDisk",
            "qemuImg",
            "seedIso",
            "seedRenderer",
            "shutdownGuest",
            "sevenZip",
            "setpriv",
            "umount",
            "wiminfo",
            "xorriso",
        ):
            replacements[token] = shlex.quote(str(unexpected))
        for token in (
            "answerTemplate",
            "autologonArchive",
            "baselineTest",
            "bootstrapScript",
            "diskPath",
            "installMarker",
            "installerDefinition",
            "isoPath",
            "mediaInspectionDirectory",
            "privateDirectory",
            "runtimeDefinition",
            "storageRoot",
            "virtioIso",
        ):
            replacements[token] = shlex.quote(str(root / token))
        replacements["sshKeygen"] = shlex.quote(required_command("ssh-keygen"))
        for token in re.findall(
            r"@([A-Za-z0-9]+)@", template.read_text(encoding="utf-8")
        ):
            if token not in replacements:
                replacements[token] = shlex.quote(required_command(token))
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
        return run_command(
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


@pytest.mark.parametrize("installing", [False, True])
def test_running_domain_stages_persistent_xml_without_restart(
    tmp_path: Path, installing: bool
) -> None:
    """Stage next-boot hardware while preserving an active installer."""
    calls = tmp_path / "calls"
    marker = tmp_path / "installing"
    if installing:
        marker.touch()
    fake_virsh = tmp_path / "virsh"
    fake_virsh.write_text(
        _shell_fixture(
            "virsh-stream-domain-xml.sh.in",
            {
                "__value0": str(required_command("bash")),
                "__value1": str(shlex.quote(str(calls))),
                "__value2": str(EXISTING_UUID),
            },
        ),
        encoding="utf-8",
    )
    fake_virsh.chmod(0o700)
    replacements = {
        "bash": required_command("bash"),
        "python": sys.executable,
        "xmlHelper": str(SETUP_TEMPLATE.parent / "libvirt_xml.py"),
        "virsh": str(fake_virsh),
        "guestName": "fixture",
        "guestUuid": EXISTING_UUID,
        "diskPath": "/fixture/VM disks/system.qcow2",
        "installMarker": str(marker),
        "libvirtUri": "qemu:///fixture",
        "runtimeDefinition": "/fixture/desired.xml",
        "autostart": "0",
    }
    source = (SETUP_TEMPLATE.parent / "libvirt-windows-vm-reconcile.sh.in").read_text(
        encoding="utf-8"
    )
    script = tmp_path / "reconcile"
    script.write_text(
        re.sub(
            r"@([A-Za-z0-9]+)@",
            lambda match: shlex.quote(replacements[match[1]]),
            source,
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [required_command("bash"), str(script)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    commands = calls.read_text(encoding="utf-8").splitlines()
    assert (
        any(" define /fixture/desired.xml --validate" in c for c in commands)
        != installing
    )
    assert not any(
        re.search(r" (destroy|shutdown|start|undefine) ", c) for c in commands
    )
    assert marker.exists() == installing


def test_doctor_uses_exact_autostart_field(tmp_path: Path) -> None:
    """A disabled one-shot autostart must not obscure persistent autostart."""
    source = (SETUP_TEMPLATE.parent / "libvirt-workstation-control.sh.in").read_text(
        encoding="utf-8"
    )
    manifest = tmp_path / "guests.tsv"
    manifest.write_text("fixture\t-\t-\t-\t0\t0\n", encoding="utf-8")
    networks = tmp_path / "networks.tsv"
    networks.touch()
    virsh = tmp_path / "virsh"
    virsh.write_text(
        _shell_fixture(
            "virsh-disabled-domain.sh.in",
            {"__value0": str(required_command("bash"))},
        ),
        encoding="utf-8",
    )
    virsh.chmod(0o700)
    replacements = {
        "bash": required_command("bash"),
        "awk": required_command("awk"),
        "grep": required_command("grep"),
        "virsh": str(virsh),
        "guestManifest": str(manifest),
        "networkManifest": str(networks),
        "vfioDeviceManifest": str(networks),
        "libvirtUri": "qemu:///fixture",
        "profileMarker": str(tmp_path / "profile"),
        "poolName": "fixture",
        "poolPath": str(tmp_path),
        "vfioProfile": "fixture",
        "emulateAarch64": "0",
        "iommuEnabled": "0",
        "storageNocow": "0",
        "vfioEnabled": "0",
    }
    # Unrelated host probes may fail, but must not affect the guest result.
    for token in re.findall(r"@([A-Za-z0-9]+)@", source):
        replacements.setdefault(token, required_command("false"))
    script = tmp_path / "doctor"
    script.write_text(
        re.sub(
            r"@([A-Za-z0-9]+)@",
            lambda match: shlex.quote(replacements[match[1]]),
            source,
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [required_command("bash"), str(script), "doctor", "fixture"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert "PASS  guest autostart is disable" in result.stdout
    assert "FAIL  guest autostart" not in result.stdout


@pytest.mark.parametrize("address_source", ["agent", "lease"])
def test_ip_handles_interface_names_with_spaces(
    tmp_path: Path, address_source: str
) -> None:
    """Return address values even when interface names occupy several fields."""
    source = (SETUP_TEMPLATE.parent / "libvirt-workstation-control.sh.in").read_text(
        encoding="utf-8"
    )
    manifest = tmp_path / "guests.tsv"
    manifest.write_text("fixture\t-\t-\t-\t0\t0\n", encoding="utf-8")
    addresses = tmp_path / "addresses.txt"
    addresses.write_text(
        " Name                     MAC address        Protocol Address\n"
        "----------------------------------------------------------\n"
        " Ethernet 2               52:54:00:00:00:10  ipv6 2001:db8::10/64\n"
        " -                        -                  ipv4 192.168.40.10/24\n"
        " Loopback Pseudo-Interface 1                  ipv6 ::1/128\n"
        " -                        -                  ipv4 127.0.0.1/8\n\n",
        encoding="utf-8",
    )
    virsh = tmp_path / "virsh"
    virsh.write_text(
        _shell_fixture(
            "virsh-interface-addresses.sh.in",
            {
                "__value0": str(required_command("bash")),
                "__value1": str(address_source),
                "__value2": str(shlex.quote(str(addresses))),
            },
        ),
        encoding="utf-8",
    )
    virsh.chmod(0o700)
    replacements = {
        "bash": required_command("bash"),
        "awk": required_command("awk"),
        "virsh": str(virsh),
        "guestManifest": str(manifest),
        "libvirtUri": "qemu:///fixture",
    }
    for token in re.findall(r"@([A-Za-z0-9]+)@", source):
        replacements.setdefault(token, required_command("false"))
    script = tmp_path / "control"
    script.write_text(
        re.sub(
            r"@([A-Za-z0-9]+)@",
            lambda match: shlex.quote(replacements[match[1]]),
            source,
        ),
        encoding="utf-8",
    )
    result = run_command(
        [required_command("bash"), str(script), "ip", "fixture"],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        "2001:db8::10",
        "192.168.40.10",
        "::1",
        "127.0.0.1",
    ]
