"""Exercise credential validation and preservation without a Google account."""

from __future__ import annotations

import configparser
import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

HELPER = runpy.run_path(
    str(Path(__file__).parents[2] / "homes/desktop/local/cloud/google_drive.py")
)


class GoogleDriveTests(unittest.TestCase):
    """Use disposable credential state and never contact Google."""

    def setUp(self) -> None:
        """Create owner-only fixture directories."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def write_client(self, data: dict) -> Path:
        """Write an owner-only client JSON fixture.

        Returns:
            The fixture file path.

        """
        path = self.root / "client.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        path.chmod(0o600)
        return path

    @staticmethod
    def client() -> dict:
        """Construct public, invalid-for-login OAuth test values.

        Returns:
            A Desktop app client fixture.

        """
        return {
            "installed": {
                "client_id": "fixture.apps.googleusercontent.com",
                "client_secret": "fixture-value",
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        }

    def test_import_preserves_literal_percent_characters(self) -> None:
        """Percent characters must not undergo configuration interpolation."""
        data = self.client()
        data["installed"]["client_secret"] = "fixture%value"
        result = HELPER["_client_configuration"](self.write_client(data))
        config = configparser.ConfigParser(interpolation=None)
        config.read_string(result)
        self.assertEqual(config["google-drive"]["client_secret"], "fixture%value")

    def test_rejects_web_clients_and_non_google_endpoints(self) -> None:
        """Do not accept credentials that redirect authorization elsewhere."""
        fixtures = [{"web": self.client()["installed"]}, self.client()]
        fixtures[1]["installed"]["token_uri"] = "https://example.invalid/token"
        for data in fixtures:
            with self.subTest(data=data), self.assertRaises(ValueError):
                HELPER["_client_configuration"](self.write_client(data))

    def test_rejects_injected_configuration_lines(self) -> None:
        """A client field must not insert a new backend configuration."""
        data = self.client()
        data["installed"]["client_id"] = "fixture\n[another-remote]"
        with self.assertRaises(ValueError):
            HELPER["_client_configuration"](self.write_client(data))

    def test_rejects_malformed_client_objects(self) -> None:
        """Malformed nested client data must produce a controlled refusal."""
        with self.assertRaises(TypeError):
            HELPER["_client_configuration"](self.write_client({"installed": []}))

    def test_rejects_shared_permissions_and_symlink_files(self) -> None:
        """Refuse credential files readable by another user or redirected."""
        client = self.write_client(self.client())
        client.chmod(0o644)
        with self.assertRaises(ValueError):
            HELPER["_client_configuration"](client)
        client.chmod(0o600)
        link = self.root / "link"
        link.symlink_to(client)
        with self.assertRaises(ValueError):
            HELPER["_client_configuration"](link)

    def test_refuses_symlink_directory_components(self) -> None:
        """Private state creation must not follow an existing directory link."""
        target = self.root / "target"
        target.mkdir()
        (self.root / "link").symlink_to(target)
        with self.assertRaises(ValueError):
            HELPER["_private_directory"](self.root / "link" / "state")
        self.assertFalse((target / "state").exists())

    def test_setup_preserves_existing_token_state(self) -> None:
        """Repeated setup must refuse to replace refreshed credentials."""
        state = self.root / "state"
        state.mkdir()
        config = state / "rclone.conf"
        config.write_bytes(b"existing refreshed credential state")
        password = self.root / "password"
        password.write_text("fixture", encoding="utf-8")
        password.chmod(0o600)
        policy = {
            "stateDirectory": str(state),
            "mountDirectory": str(self.root / "mount"),
            "passwordFile": str(password),
        }
        with self.assertRaises(ValueError):
            HELPER["_setup"](policy)
        self.assertEqual(config.read_bytes(), b"existing refreshed credential state")

    def test_refuses_plaintext_token_configuration(self) -> None:
        """Starting a mount must not silently accept plaintext credentials."""
        config = self.root / "rclone.conf"
        config.write_text("[google-drive]\ntoken = fixture\n", encoding="utf-8")
        config.chmod(0o600)
        with self.assertRaises(ValueError):
            HELPER["_encrypted_file"](config)

    def test_initialization_does_not_change_mounted_directory(self) -> None:
        """Activation must not chmod or traverse an already mounted remote."""
        mount = self.root / "mount"
        policy = {
            "stateDirectory": str(self.root / "state"),
            "mountDirectory": str(mount),
        }
        with patch.object(os.path, "ismount", return_value=True):
            HELPER["_initialize"](policy)
        self.assertFalse(mount.exists())

    def test_notification_failure_does_not_stop_upload_worker(self) -> None:
        """A missing or stalled notification daemon must not kill the mount."""
        for error in [OSError("fixture"), subprocess.TimeoutExpired("fixture", 10)]:
            command = Mock(side_effect=error)
            with (
                self.subTest(error=error),
                patch.dict(HELPER["_notify"].__globals__, run_command=command),
            ):
                HELPER["_notify"]({"notify": "/fixture/notify"}, "public status")
                command.assert_called_once()


if __name__ == "__main__":
    unittest.main()
