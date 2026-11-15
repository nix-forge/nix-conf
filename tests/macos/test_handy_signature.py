"""Verify Handy's final native bundle with Apple's authoritative verifier."""

import os
import plistlib
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
import unittest
from pathlib import Path


@unittest.skipUnless(sys.platform == "darwin", "Apple verification requires macOS")
class HandySignatureTests(unittest.TestCase):
    """Check the installed artifact rather than its source signing metadata."""

    def test_bundle_identity_and_resource_seal(self) -> None:
        """Require a sealed bundle that can request microphone access."""
        location = os.environ.get("HANDY_TEST_BUNDLE")
        if not location:
            self.skipTest("Set HANDY_TEST_BUNDLE to the built or installed app")
        bundle = Path(location)
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.pais.handy")
        self.assertTrue(info.get("NSMicrophoneUsageDescription"))
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Absolute Apple verifier and a test-owned bundle path.
            [
                "/usr/bin/codesign",
                "--verify",
                "--deep",
                "--strict",
                "--all-architectures",
                str(bundle),
            ],
            check=True,
        )


if __name__ == "__main__":
    unittest.main()
