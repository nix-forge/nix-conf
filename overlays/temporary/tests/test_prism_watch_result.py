"""Reject unrelated failures and skips in the Prism native proof."""

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import] - Write inert XML regression fixtures only.
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "prism_watch_result", Path(__file__).with_name("prism-watch-result.py")
)
if _SPEC is None or _SPEC.loader is None:
    message = "Cannot load the local proof classifier"
    raise ImportError(message)
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)


class WatchResultTest(unittest.TestCase):
    """Exercise accepted evidence and rejection of unrelated failures."""

    @staticmethod
    def check(mode: str, changes: dict[str, tuple[str, str]]) -> None:
        """Create native-result fixtures and apply the real classifier."""
        root = ET.Element("TestCase", name="ResourceFolderModelTest")
        for name in [
            "initTestCase",
            "test_1178",
            "test_addFromWatch",
            "test_removeResource",
            "test_enable_disable",
            "cleanupTestCase",
        ]:
            kind, message = changes.get(name, ("pass", ""))
            function = ET.SubElement(root, "TestFunction", name=name)
            incident = ET.SubElement(function, "Incident", type=kind)
            ET.SubElement(incident, "Description").text = message
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / "result.xml"
            ET.ElementTree(root).write(result)
            _MODULE.verify(result, mode)

    def test_expected_watch_timeout(self) -> None:
        """Test expected watch timeout."""
        self.check(
            "unavailable",
            {
                "test_removeResource": (
                    "fail",
                    "Timer has expired. The update never finished.",
                )
            },
        )

    def test_expected_missing_resource_update(self) -> None:
        """Test expected missing resource update."""
        self.check(
            "unavailable",
            {
                "test_removeResource": (
                    "fail",
                    "Compared values are not the same: Actual (model.size()): 1 Expected: 2",
                )
            },
        )

    def test_exact_capability_skip(self) -> None:
        """Test exact capability skip."""
        self.check(
            "skip",
            {
                "test_removeResource": (
                    "skip",
                    "Native filesystem notifications are unavailable",
                )
            },
        )

    def test_capability_present_executes_all_cases(self) -> None:
        """Test capability present executes all cases."""
        self.check("present", {})

    def test_unrelated_baseline_failure_rejected(self) -> None:
        """Test unrelated baseline failure rejected."""
        with self.assertRaisesRegex(ValueError, "watcher-dependent"):  # ruff: ignore[pytest-unittest-raises-assertion] - Run standard library regression tests without pytest.
            self.check(
                "unavailable",
                {"test_removeResource": ("fail", "tmp.isValid() returned FALSE")},
            )

    def test_other_case_failure_rejected(self) -> None:
        """Test other case failure rejected."""
        with self.assertRaisesRegex(ValueError, "Unexpected fail"):  # ruff: ignore[pytest-unittest-raises-assertion] - Run standard library regression tests without pytest.
            self.check(
                "skip",
                {
                    "test_removeResource": (
                        "skip",
                        "Native filesystem notifications are unavailable",
                    ),
                    "test_1178": ("fail", "unrelated failure"),
                },
            )

    def test_capable_case_cannot_skip(self) -> None:
        """Test capable case cannot skip."""
        with self.assertRaisesRegex(ValueError, "Unexpected skip"):  # ruff: ignore[pytest-unittest-raises-assertion] - Run standard library regression tests without pytest.
            self.check(
                "present",
                {
                    "test_removeResource": (
                        "skip",
                        "Native filesystem notifications are unavailable",
                    )
                },
            )

    def test_other_case_cannot_skip(self) -> None:
        """Test other case cannot skip."""
        with self.assertRaisesRegex(ValueError, "Unexpected skip"):  # ruff: ignore[pytest-unittest-raises-assertion] - Run standard library regression tests without pytest.
            self.check("present", {"test_addFromWatch": ("skip", "disabled")})

    def test_missing_suite_rejected(self) -> None:
        """Test missing suite rejected."""
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / "result.xml"
            result.write_text(
                '<TestCase><TestFunction name="test_removeResource"><Incident type="pass"/></TestFunction></TestCase>'
            )
            with self.assertRaisesRegex(ValueError, "full ResourceFolderModel"):  # ruff: ignore[pytest-unittest-raises-assertion] - Run standard library regression tests without pytest.
                _MODULE.verify(result, "present")


if __name__ == "__main__":
    unittest.main()
