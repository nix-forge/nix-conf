"""Reject ambiguous event-delivery claims before any guard review."""

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "deploy_watch_pair", Path(__file__).with_name("deploy-watch-pair.py")
)
if SPEC is None or SPEC.loader is None:
    message = "Cannot load reviewed local proof classifier"
    raise ImportError(message)
PAIR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PAIR)


class PairTest(unittest.TestCase):
    """The proof requires measured event loss and a passing identical-binary control."""

    def setUp(self) -> None:
        """Create independently structured raw and capability-present receipts."""
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.strict = Path(self.directory.name) / "strict"
        self.control = Path(self.directory.name) / "control"
        for folder, status, callbacks in (
            (self.strict, 101, 0),
            (self.control, 0, 1),
        ):
            folder.mkdir()
            (folder / "status.json").write_text(
                json.dumps({
                    "exit": status,
                    "binarySha256": "a" * 64,
                    "probeSha256": "b" * 64,
                })
            )
            (folder / "fsevents.json").write_text(
                json.dumps({
                    "validDirectory": True,
                    "createdStream": True,
                    "startedStream": True,
                    "removedCanary": True,
                    "removeCallbacks": callbacks,
                    "windowSeconds": 10,
                })
            )
        (self.strict / "test.log").write_text(
            f"test {PAIR.CASE} ... FAILED\nobserve canary removal: TimesUp\n"
            "0 passed; 1 failed; 0 ignored"
        )
        (self.control / "test.log").write_text(
            f"test {PAIR.CASE} ... ok\n1 passed; 0 failed; 0 ignored"
        )

        for index, case in enumerate(PAIR.WATCH_CASES[1:], 1):
            (self.control / f"watch-{index}.log").write_text(
                f"test {case} ... ok\n1 passed; 0 failed; 0 ignored"
            )
            (self.control / f"watch-{index}.json").write_text(json.dumps({"exit": 0}))

    @staticmethod
    def update(folder: Path, name: str, key: str, value: object) -> None:
        """Alter one evidence condition without rewriting the rest of the pair."""
        path = folder / name
        record = json.loads(path.read_text())
        record[key] = value
        path.write_text(json.dumps(record))

    def test_matched_pair(self) -> None:
        """Accept only the measured differential, without claiming denial."""
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            PAIR.compare(self.strict, self.control)
        self.assertIn("no permission-denial claim", output.getvalue())  # ruff: ignore[pytest-unittest-assertion] - Standard library fixture assertion.

    def test_generic_failure(self) -> None:
        """A generic Rust failure cannot certify this specific environment difference."""
        (self.strict / "test.log").write_text("compiler failed")
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_host_timeout(self) -> None:
        """Failure of the control preserves the real unresolved problem."""
        self.update(self.control, "status.json", "exit", 101)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_host_no_callbacks(self) -> None:
        """A second callback timeout is not capability-present evidence."""
        self.update(self.control, "fsevents.json", "removeCallbacks", 0)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_strict_callbacks(self) -> None:
        """Delivery in the sandbox requires investigating testcase timing."""
        self.update(self.strict, "fsevents.json", "removeCallbacks", 1)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_host_positive_allows_strict_delivery(self) -> None:
        """A healthy host gate remains automatic if sandbox capability improves."""
        self.update(self.strict, "fsevents.json", "removeCallbacks", 1)
        self.update(self.strict, "status.json", "exit", 0)
        (self.strict / "test.log").write_text(
            f"test {PAIR.CASE} ... ok\n1 passed; 0 failed; 0 ignored"
        )
        PAIR.require_host_control(self.strict, self.control)

    def test_host_positive_rejects_failed_confirmation(self) -> None:
        """The required runtime gate cannot pass a host confirmation timeout."""
        self.update(self.control, "status.json", "exit", 101)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.require_host_control(self.strict, self.control)

    def test_invalid_directory(self) -> None:
        """An absent real writable directory cannot masquerade as event loss."""
        self.update(self.strict, "fsevents.json", "validDirectory", False)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_different_binaries(self) -> None:
        """Prevent different source builds from manufacturing a differential."""
        self.update(self.control, "status.json", "binarySha256", "c" * 64)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_unknown_mach_service(self) -> None:
        """An unknown service code alone cannot replace the exact Rust symptom."""
        (self.strict / "test.log").write_text("bootstrap_lookup error1102")
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_other_host_watcher_failed(self) -> None:
        """Keep all three original watcher cases mandatory in the host control."""
        self.update(self.control, "watch-1.json", "exit", 101)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)

    def test_host_start_failed(self) -> None:
        """A failed FSEvents start cannot certify capability presence."""
        self.update(self.control, "fsevents.json", "startedStream", False)
        with self.assertRaises(ValueError):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library fixtures need no pytest.
            PAIR.compare(self.strict, self.control)


if __name__ == "__main__":
    unittest.main()
