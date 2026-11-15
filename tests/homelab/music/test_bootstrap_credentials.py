"""Music bootstrap credentials stay out of child process argument lists."""

import json
import os
import shlex
import shutil
import stat
import subprocess  # ruff: ignore[suspicious-subprocess-import] - execute isolated production script fixtures
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = (
    Path(__file__).resolve().parents[3]
    / "hosts/nixos/desktop/local/homelab/music/scripts"
)
FIXTURE = Path(__file__).parent / "fixtures/record_bootstrap_command.py"
TOKEN = "public-bootstrap-token-canary"  # ruff: ignore[hardcoded-password-string] - disposable public fixture marker


class BootstrapCredentialsTest(unittest.TestCase):
    """Exercise real jq rendering and filesystem writes with recorded argv."""

    def setUp(self) -> None:
        """Prepare existing accounts and transparent command adapters."""
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commands = self.root / "bin"
        self.commands.mkdir()
        self.credentials = self.root / "credentials"
        self.credentials.mkdir(mode=0o700)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.argv_log = self.root / "argv.jsonl"
        self.plugin_config = self.root / "plugin.json"
        real_commands = {}
        for name in ["jq", "printf", "chmod", "mv", "rm"]:
            executable = shutil.which(name)
            assert executable is not None, name
            real_commands[name] = executable
        for name in [
            *real_commands,
            "curl",
            "navidrome",
            "resolve-users",
            "link-listenbrainz",
            "lyrics",
            "expect",
        ]:
            script = self.commands / name
            script.write_text(f"#!{sys.executable}\n" + FIXTURE.read_text())
            script.chmod(0o700)
        accounts = ["admin", "service", "feishin", "listener"]
        for credential, value in [
            ("navidrome-admin-username", "admin"),
            ("navidrome-service-username", "service"),
            ("feishin-listener-username", "feishin"),
        ]:
            (self.credentials / credential).write_text(value)
        (self.credentials / "listenbrainz-identity").write_text(
            json.dumps({
                "navidromeUsername": "listener",
                "listenbrainzUsername": "public-fixture-listener",
                "token": "public-fixture-token",
            })
        )
        self.environment = {
            **os.environ,
            "PATH": f"{self.commands}{os.pathsep}{os.environ['PATH']}",
            "CREDENTIALS_DIRECTORY": str(self.credentials),
            "RUNTIME_DIRECTORY": str(self.runtime),
            "ARGV_LOG": str(self.argv_log),
            "PLUGIN_CONFIG": str(self.plugin_config),
            "FIXTURE_USERS": json.dumps([{"username": name} for name in accounts]),
            "REAL_COMMANDS": json.dumps(real_commands),
        }

    def run_script(
        self, name: str, replacements: dict[str, str]
    ) -> subprocess.CompletedProcess[str]:
        """Render the production script and execute its control flow.

        Returns:
            Exit status and captured diagnostics from the isolated script.

        """
        content = (SCRIPTS / name).read_text()
        for key, value in replacements.items():
            content = content.replace(f"@{key}@", value)
        script = self.root / name
        script.write_text(content)
        bash = shutil.which("bash")
        assert bash is not None
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed local Bash with rendered fixture input
            [bash, str(script)],
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )

    def bootstrap(self) -> subprocess.CompletedProcess[str]:
        """Use real JSON processing with external service calls isolated.

        Returns:
            Exit status and diagnostics from the bootstrap fixture.

        """
        return self.run_script(
            "music-discovery-bootstrap.sh",
            {
                "toString_navidromePort": "14533",
                "navidromeConfig": shlex.quote(str(self.root / "navidrome.toml")),
                "pkgs_writeText_create_navidrome_user_expect_set_timeout_30_l": "unused",
                "lib_getExe_resolvePluginUserIds": shlex.quote(
                    str(self.commands / "resolve-users")
                ),
                "linkListenBrainz": shlex.quote(
                    str(self.commands / "link-listenbrainz")
                ),
                "configureLyricsPlugin": shlex.quote(str(self.commands / "lyrics")),
                "lyricsPluginConfig": shlex.quote(str(self.root / "lyrics.json")),
                "toString_audioMusePort": "18000",
                "lib_escapeShellArg_audioMuseHouseholdApproval": shlex.quote(
                    str(self.root / "approval")
                ),
            },
        )

    def assert_private_arguments(
        self, result: subprocess.CompletedProcess[str]
    ) -> None:
        """Neither child argv nor command diagnostics may disclose the token."""
        self.assertNotIn(TOKEN, self.argv_log.read_text())
        self.assertNotIn(TOKEN, result.stdout + result.stderr)

    def test_bootstrap_reads_token_privately_and_preserves_value_semantics(
        self,
    ) -> None:
        """Strip terminal LF only, while retaining embedded LF, CR and spaces."""
        for value in [
            TOKEN,
            TOKEN + "\n\n",
            " " + TOKEN + " \r\n",
            TOKEN + "\ninside\n",
        ]:
            with self.subTest(value=value):
                (self.credentials / "audiomuse-api-token").write_bytes(value.encode())
                result = self.bootstrap()
                self.assertEqual(result.returncode, 0, result.stderr)
                config = json.loads(self.plugin_config.read_text())
                self.assertEqual(config["apiToken"], value.rstrip("\n"))
                self.assertEqual(config["apiUrl"], "http://127.0.0.1:18000")
                self.assertTrue(config["eliminateDuplicates"])
                self.assert_private_arguments(result)
                self.assertFalse((self.runtime / "audiomuse-plugin.json").exists())

    def test_missing_token_prevents_plugin_write(self) -> None:
        """A failed credential read must not configure the AudioMuse plugin."""
        result = self.bootstrap()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.plugin_config.exists())

    def test_projector_preserves_exact_private_bytes_without_external_argv(
        self,
    ) -> None:
        """Keep file permissions and all input bytes without an argv exposure."""
        value = " " + TOKEN + "\r\n\n"
        self.environment["API_TOKEN"] = value
        target = self.root / "projected-token"
        result = self.run_script(
            "project-audiomuse-api-token.sh",
            {
                "lib_escapeShellArg_bootstrapAudioMuseCredential": shlex.quote(
                    str(target)
                ),
                "pkgs_coreutils": shlex.quote(str(self.root)),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), value.encode())
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o400)
        self.assertFalse(target.with_suffix(".partial").exists())
        self.assert_private_arguments(result)
