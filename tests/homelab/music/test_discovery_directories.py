"""Directory preparation restores traversal without exposing backup contents."""

import grp
import os
import pwd
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

TRAVERSE_MODE = 0o711
PRIVATE_MODE = 0o700
SHARED_MUSIC_MODE = 0o2770 if os.getuid() == 0 else 0o770


class DirectoryPreparationTest(unittest.TestCase):
    """Exercise the script against an old private parent directory."""

    def test_repairs_backup_parent_without_exposing_backup_leaves(self) -> None:
        """Both backup users can traverse the parent, but not each other's leaf."""
        owner = pwd.getpwuid(os.getuid()).pw_name
        group = grp.getgrgid(os.getgid()).gr_name
        bash = shutil.which("bash")
        assert bash is not None
        script = (
            Path(__file__).resolve().parents[3]
            / "hosts/nixos/desktop/local/homelab/music/scripts/prepare-music-discovery-directories.sh"
        )

        with tempfile.TemporaryDirectory() as directory:
            media_root = Path(directory) / "media"
            discovery_root = media_root / ".services/music-discovery"
            discovery_root.mkdir(parents=True)
            discovery_root.chmod(PRIVATE_MODE)
            music_folder = media_root / "library/music"

            subprocess.run(
                [
                    bash,
                    str(script),
                    str(media_root),
                    str(music_folder),
                    group,
                    owner,
                    group,
                    owner,
                    group,
                    owner,
                    group,
                ],
                check=True,
            )

            def mode(path: Path) -> int:
                return stat.S_IMODE(path.stat().st_mode)

            self.assertEqual(mode(discovery_root), TRAVERSE_MODE)
            self.assertEqual(mode(discovery_root / "backups"), TRAVERSE_MODE)
            self.assertEqual(mode(discovery_root / "backups/navidrome"), PRIVATE_MODE)
            self.assertEqual(mode(discovery_root / "backups/audiomuse"), PRIVATE_MODE)
            self.assertEqual(mode(music_folder), SHARED_MUSIC_MODE)


if __name__ == "__main__":
    unittest.main()
