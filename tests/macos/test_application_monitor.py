"""Host integration proof for launch and filesystem notifications without polling."""

from __future__ import annotations

import json
import os
import plistlib
import signal
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable native fixture only.
import sys
import tempfile
import time
from contextlib import suppress
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]
MAX_RESTART_INTERVAL = 30
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


@pytest.mark.nix_integration
@pytest.mark.skipif(
    sys.platform != "darwin", reason="Native AppKit and FSEvents host integration"
)
def test_monitor_observes_initial_nested_files_and_app_lifecycle(
    tmp_path: Path,
) -> None:
    """Require real callbacks for initial state, nested changes, launch and exit."""
    monitor = tmp_path / "monitor"
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Owned native fixture and explicit argv.
        [
            "/usr/bin/xcrun",
            "swiftc",
            "-swift-version",
            "5",
            str(ROOT / "modules/home/macos/application-monitor.swift"),
            "-o",
            str(monitor),
        ],
        check=True,
    )
    bundle = tmp_path / "Observer Fixture.app"
    binary = bundle / "Contents/MacOS/fixture"
    binary.parent.mkdir(parents=True)
    swift = tmp_path / "fixture.swift"
    swift.write_text(
        "import AppKit\nlet app = NSApplication.shared\napp.setActivationPolicy(.accessory)\napp.run()\n"
    )
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Owned native fixture and explicit argv.
        ["/usr/bin/xcrun", "swiftc", str(swift), "-o", str(binary)], check=True
    )
    identifier = "org.example.lifecycle-monitor-fixture"
    (bundle / "Contents/Info.plist").write_bytes(
        plistlib.dumps({
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "fixture",
            "CFBundlePackageType": "APPL",
            "LSUIElement": True,
        })
    )
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Owned native fixture and explicit argv.
        ["/usr/bin/codesign", "--force", "--sign", "-", str(bundle)],
        check=True,
        capture_output=True,
    )
    apps = tmp_path / "Applications/Managed"
    marker = apps / "nested/marker"
    marker.parent.mkdir(parents=True)
    marker.write_text("initial")
    stub = tmp_path / "snapshot.py"
    stub.write_text("""import json,pathlib,socket,subprocess,sys
address,marker,query,identifier=sys.argv[1:]
data=json.loads(subprocess.check_output(['/usr/bin/osascript','-l','JavaScript',query,identifier],text=True))
result={'marker':pathlib.Path(marker).read_text(),'running':data[identifier]['running']}
with socket.socket(socket.AF_UNIX) as client:
    client.connect(address)
    client.sendall(json.dumps(result).encode())
""")
    address = Path(tempfile.mkdtemp(prefix="hm-events-")) / "events.sock"
    deadline = time.monotonic() + 30
    live = []
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(str(address))
        listener.listen()

        def receive() -> dict:
            """Block on native callbacks within one deadline.

            Returns:
                A complete helper snapshot.

            """
            listener.settimeout(max(0.01, deadline - time.monotonic()))
            with listener.accept()[0] as connection:
                return json.loads(connection.recv(65536))

        with subprocess.Popen([  # ruff: ignore[subprocess-without-shell-equals-true] - Owned monitor fixture.
            str(monitor),
            str(apps),
            sys.executable,
            str(stub),
            str(address),
            str(marker),
            str(ROOT / "modules/home/macos/scripts/application-paths.js"),
            identifier,
        ]) as process:
            try:
                assert receive()["marker"] == "initial"
                marker.write_text("changed")
                while receive()["marker"] != "changed":
                    pass  # Blocking callback receive, never a status poll.
                subprocess.run(["/usr/bin/open", "-a", str(bundle)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - Open disposable accessory fixture.
                while not live:
                    live = receive()["running"]
                assert len(live) == 1
                os.kill(live[0]["pid"], signal.SIGTERM)
                while receive()["running"]:
                    pass
            finally:
                process.terminate()
                process.wait()
                for app in live:
                    with suppress(ProcessLookupError):
                        os.kill(app["pid"], signal.SIGTERM)
                address.unlink(missing_ok=True)
                address.parent.rmdir()
                subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Owned native fixture and explicit argv.
                    [LSREGISTER, "-u", str(bundle)], check=False, capture_output=True
                )


@pytest.mark.nix_integration
@pytest.mark.skipif(sys.platform != "darwin", reason="Native launchd recovery")
def test_registry_job_retries_failure_and_stops_after_success(tmp_path: Path) -> None:
    """Exercise the installed service's retry policy in a disposable user job."""
    installed = Path(
        "/Library/LaunchDaemons/org.nixos.macos-application-registry.plist"
    )
    if not installed.exists():
        pytest.skip("Protected registry daemon is not configured on this Mac")
    config = plistlib.loads(installed.read_bytes())
    assert config["KeepAlive"] == {"SuccessfulExit": False}
    assert config["RunAtLoad"] is True
    throttle = config["ThrottleInterval"]
    assert (
        0 < throttle <= MAX_RESTART_INTERVAL
    )  # Recovery is rate-limited, not abandoned.
    address = Path(tempfile.mkdtemp(prefix="hm-retry-")) / "events.sock"
    label = f"org.example.registry-retry-{os.getpid()}"
    domain = f"gui/{os.getuid()}"
    watch = tmp_path / "watched"
    watch.mkdir()
    config.update({
        "Label": label,
        "ProgramArguments": [
            sys.executable,
            str(ROOT / "tests/macos/fixtures/registry_retry.py"),
            str(address),
            str(tmp_path / "attempted"),
        ],
        "WatchPaths": [str(watch)],
        "StandardOutPath": str(tmp_path / "stdout"),
        "StandardErrorPath": str(tmp_path / "stderr"),
    })
    plist = tmp_path / "job.plist"
    plist.write_bytes(plistlib.dumps(config))
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(str(address))
        listener.listen()
        try:
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Disposable fixture job.
                ["/bin/launchctl", "bootstrap", domain, str(plist)],
                check=True,
                capture_output=True,
            )
            listener.settimeout(throttle + 15)
            with listener.accept()[0] as connection:
                assert connection.recv(100) == b"failed"
            with listener.accept()[0] as connection:
                assert connection.recv(100) == b"recovered"
            # No new watch events: success must stay dormant for a full restart interval.
            listener.settimeout(throttle + 2)
            with pytest.raises(TimeoutError):
                listener.accept()
        finally:
            subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Remove only our owned fixture.
                ["/bin/launchctl", "bootout", f"{domain}/{label}"],
                check=False,
                capture_output=True,
            )
            address.unlink(missing_ok=True)
            address.parent.rmdir()
