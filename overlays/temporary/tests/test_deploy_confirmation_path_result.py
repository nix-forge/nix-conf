"""Require actual helper execution and distinguish alias failure from test setup."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "path_result", Path(__file__).with_name("deploy-confirmation-path-result.py")
)
if _SPEC is None or _SPEC.loader is None:
    message = "Cannot load reviewed path proof"
    raise ImportError(message)
_RESULT = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RESULT)


class PathResultTest(unittest.TestCase):
    """Never treat missing callbacks or invalid fixtures as repaired behavior."""

    def setUp(self) -> None:
        """Prepare receipts independently from the classifier implementation."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)

    def receipt(self, index: int, status: int, log: str) -> None:
        """Record one exact real helper case outcome."""
        (self.path / f"directory-{index}.json").write_text(json.dumps({"exit": status}))
        (self.path / f"directory-{index}.log").write_text(log)

    def test_normal_pass(self) -> None:
        """The native original-directory path must remain working."""
        self.receipt(
            0,
            0,
            "test tests::confirmation_watcher_observes_normal_directory_removal ... ok\n1 passed; 0 failed; 0 ignored",
        )
        _RESULT.require_case(self.path, 0, passing=True)

    def test_alias_pass(self) -> None:
        """The repaired real symlink alias must receive immediate removal."""
        self.receipt(
            1,
            0,
            "test tests::confirmation_watcher_observes_symlink_directory_removal ... ok\n1 passed; 0 failed; 0 ignored",
        )
        _RESULT.require_case(self.path, 1, passing=True)

    def test_precise_alias_baseline(self) -> None:
        """Require the source-backed original path comparator's exact failure."""
        self.receipt(
            1,
            101,
            "test tests::confirmation_watcher_observes_symlink_directory_removal ... FAILED\nobserve real directory canary removal: TimesUp\n0 passed; 1 failed; 0 ignored",
        )
        _RESULT.require_case(self.path, 1, passing=False)

    def test_setup_failure_rejected(self) -> None:
        """Missing or invalid symlinks cannot certify a path-comparison defect."""
        self.receipt(1, 101, "create directory alias: permission denied")
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            _RESULT.require_case(self.path, 1, passing=False)

    def test_timeout_rejected_as_positive(self) -> None:
        """A callback timeout never passes the repaired alias gate."""
        self.receipt(1, 101, "observe real directory canary removal: TimesUp")
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            _RESULT.require_case(self.path, 1, passing=True)

    def test_zero_tests_rejected(self) -> None:
        """Selecting no matching test is not a successful real helper probe."""
        self.receipt(1, 0, "0 passed; 0 failed; 0 ignored")
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            _RESULT.require_case(self.path, 1, passing=True)


if __name__ == "__main__":
    unittest.main()
