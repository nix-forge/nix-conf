"""Check isolated runner cleanup with mocked children and no compositor access."""

from __future__ import annotations

import os
import runpy
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Fixed fixture children.
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from watchdog.events import FileCreatedEvent, FileOpenedEvent

_MODULE = runpy.run_path(str(Path(__file__).with_name("run_upstream_local.py")))


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
                patch.dict(
                    _MODULE["_Runner"].run.__globals__,
                    _wait_child=lambda child, _timeout: child.wait(),
                    sleep=lambda _seconds: None,
                ),
                self.assertRaises(RuntimeError),
            ):
                runner.run()
            self.assertEqual({args[0][0] for args in kill.call_args_list}, {401, 402})
            for pid in (401, 402):
                kill.assert_any_call(pid, signal.SIGTERM)
                kill.assert_any_call(pid, signal.SIGKILL)
            for child in children:
                child.wait.assert_called_once_with()
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


class NotificationWaitTests(unittest.TestCase):
    """Wait for state changes without repeated probes or lost notifications."""

    def test_idle_wait_probes_only_once(self) -> None:
        """An unchanged directory consumes the deadline in one blocking wait."""
        with tempfile.TemporaryDirectory() as directory:
            predicate = Mock(return_value=False)
            changes = _MODULE["_Changes"](Path(directory))
            # This case exercises the condition deadline, not native delivery.
            changes.observer = Mock()
            self.assertFalse(changes.wait(predicate, 0.05))
            predicate.assert_called_once_with()

    def test_change_during_probe_is_not_lost(self) -> None:
        """Notification between snapshot and wait triggers another state check."""
        with tempfile.TemporaryDirectory() as directory:
            changes = _MODULE["_Changes"](Path(directory))
            changes.observer = Mock()

            def predicate() -> bool:
                if changes.generation:
                    return True
                changes.on_any_event(FileCreatedEvent(directory + "/ready"))
                return False

            self.assertTrue(changes.wait(predicate, 1))

    def test_real_filesystem_notification(self) -> None:
        """Creation after registration wakes a waiter using native file events."""
        with tempfile.TemporaryDirectory() as directory:
            changes = _MODULE["_Changes"](Path(directory))
            ready = Path(directory) / "ready"
            probes = 0

            def predicate() -> bool:
                nonlocal probes
                probes += 1
                if probes == 1:
                    ready.touch()
                    return False
                return ready.exists()

            self.assertTrue(changes.wait(predicate, 2))
            self.assertGreaterEqual(probes, 2)

    def test_reads_do_not_trigger_another_probe(self) -> None:
        """Predicate reads cannot create a notification loop."""
        with tempfile.TemporaryDirectory() as directory:
            changes = _MODULE["_Changes"](Path(directory))
            changes.on_any_event(FileOpenedEvent(directory + "/status"))
            self.assertEqual(changes.generation, 0)

    @unittest.skipUnless(
        hasattr(os, "pidfd_open"), "The compositor runner requires Linux"
    )
    def test_child_exit_and_deadline(self) -> None:
        """Child notifications preserve exit status and leave timeout cancellation owned."""
        wait_child = _MODULE["_wait_child"]
        with subprocess.Popen([sys.executable, "-c", "raise SystemExit(7)"]) as child:
            self.assertEqual(wait_child(child, 5), 7)
            self.assertEqual(wait_child(child, 0), 7)
        with subprocess.Popen(
            [sys.executable, "-c", "import sys; sys.stdin.buffer.read()"],
            stdin=subprocess.PIPE,
        ) as child:
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    wait_child(child, 0.01)
                self.assertIsNone(child.returncode)
            finally:
                child.terminate()
                child.wait()
