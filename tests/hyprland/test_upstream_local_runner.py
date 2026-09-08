"""Check isolated runner cleanup with mocked children and no compositor access."""

from __future__ import annotations

import os
import runpy
import signal
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, call, patch

_MODULE = runpy.run_path(str(Path(__file__).with_name("run-upstream-local.py")))


class UpstreamRunnerTests(unittest.TestCase):
    """Preserve isolation settings, process cleanup, and failure evidence."""

    def test_environment_disconnects_desktop(self) -> None:
        """Inherited display, session, and compositor endpoints are replaced."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            inherited = {
                "DISPLAY": ":0",
                "WAYLAND_SOCKET": "5",
                "SESSION_MANAGER": "desktop",
                "WAYLAND_DISPLAY": "wayland-real",
                "HYPRLAND_INSTANCE_SIGNATURE": "real",
                "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
            }
            with patch.dict(os.environ, inherited, clear=True):
                env = _MODULE["_environment"](root, root / "evidence")
            self.assertTrue(
                {"DISPLAY", "WAYLAND_SOCKET", "SESSION_MANAGER"}.isdisjoint(env),
            )
            self.assertEqual(env["WAYLAND_DISPLAY"], str(root / "absent"))
            self.assertEqual(env["HYPRLAND_INSTANCE_SIGNATURE"], "")
            self.assertEqual(
                env["DBUS_SESSION_BUS_ADDRESS"], f"unix:path={root}/no-bus"
            )

    def test_failed_run_stops_children_and_collects_logs(self) -> None:
        """A failed test still terminates only its children and records failure."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / "evidence"
            runtime = root / "runtime"
            evidence.mkdir()
            runtime.mkdir()
            (runtime / "compositor.log").write_text("fixture log\n", encoding="utf-8")
            options = _MODULE["_Options"](root, evidence, "unused-cage", False, [])
            children = [Mock(pid=401), Mock(pid=402)]
            runner = _MODULE["_Runner"](options, runtime, {}, children)
            failure = RuntimeError("fixture failure")
            with (
                patch.object(type(runner), "_start_parent"),
                patch.object(type(runner), "_run_tests", side_effect=failure),
                patch("os.killpg") as kill,
                patch("time.sleep"),
                self.assertRaises(RuntimeError),  # ruff: ignore[pytest-unittest-raises-assertion] - No pytest dependency.
            ):
                runner.run()
            self.assertEqual(
                kill.call_args_list,
                [
                    call(402, signal.SIGTERM),
                    call(401, signal.SIGTERM),
                    call(402, signal.SIGKILL),
                    call(401, signal.SIGKILL),
                ],
            )
            for child in children:
                child.wait.assert_called_once_with(timeout=5)
            self.assertEqual(
                (evidence / "exit-status.txt").read_text(encoding="utf-8"), "1\n"
            )
            self.assertEqual(
                (evidence / "compositor.log").read_text(encoding="utf-8"),
                "fixture log\n",
            )

    def test_crash_report_changes_only_success_status(self) -> None:
        """Crash artifacts turn success into failure without masking another error."""
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            (evidence / "hyprlandCrashReport-fixture.txt").touch()
            record = _MODULE["_record_result"]
            self.assertEqual(record(evidence, 0), 2)
            self.assertEqual(record(evidence, 7), 7)


if __name__ == "__main__":
    unittest.main()
