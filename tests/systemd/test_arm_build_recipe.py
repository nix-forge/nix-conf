"""Exercise ARM build dispatch without starting Nix workloads."""

import json
import os
import re
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - exercise the local recipe with controlled tools.
import sys
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MOCK_EXIT_STATUS = 7


@pytest.mark.parametrize(
    "repository", [".", "pkgs", "nix-seal", "nix-config-framework", "nix-homelab"]
)
@pytest.mark.parametrize(
    "build_system", ["x86_64-linux", "aarch64-linux", "aarch64-darwin"]
)
@pytest.mark.parametrize("target", ["x86_64-linux", "aarch64-linux"])
def test_arm_dispatch_stays_on_desktop(
    tmp_path: Path, repository: str, build_system: str, target: str
) -> None:
    """Every repository uses its ordinary ARM exports through the desktop queue."""
    host = "macbook" if build_system.endswith("darwin") else "desktop"
    just = shutil.which("just")
    assert just is not None
    bash = shutil.which("bash")
    assert bash is not None
    tools = tmp_path / "bin"
    tools.mkdir()
    calls = tmp_path / "calls.jsonl"
    (tools / "hostname").write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: {"__fixture_0__": f"{host}"}[match[0]],
            (Path(__file__).with_name("fixtures") / "hostname.sh.in")
            .read_text(encoding="utf-8")
            .replace("@bash@", bash),
        )
    )
    (tools / "workstation-task").write_text(
        re.sub(
            r"__fixture_[0-9]+__",
            lambda match: {
                "__fixture_0__": f"{sys.executable}",
                "__fixture_1__": str(
                    (
                        Path(__file__).with_name("fixtures") / "arm_workstation_task.py"
                    ).read_text(encoding="utf-8")
                ),
            }[match[0]],
            (
                Path(__file__).with_name("fixtures") / "workstation_task_launcher.py.in"
            ).read_text(encoding="utf-8"),
        )
    )
    (tools / "nix").write_text(
        (Path(__file__).with_name("fixtures") / "nix_build_system.py.in")
        .read_text()
        .replace("@python@", sys.executable)
    )
    (tools / "nix-store").write_text(
        (Path(__file__).with_name("fixtures") / "nix-store-source-root.sh.in")
        .read_text()
        .replace("@bash@", bash)
    )
    for tool in tools.iterdir():
        tool.chmod(0o755)
    environment = os.environ | {
        "PATH": f"{tools}:{os.environ['PATH']}",
        "ARM_TEST_CALLS": str(calls),
        "ARM_TEST_EXIT": str(MOCK_EXIT_STATUS),
        "ARM_TEST_BUILD_SYSTEM": build_system,
        "XDG_STATE_HOME": str(tmp_path / "state"),
    }
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed local executable and fixture arguments.
        [
            just,
            "--justfile",
            str(REPOSITORY_ROOT / "justfile"),
            "--set",
            "task",
            "workstation-task" if host == "desktop" else "",
            "linux-build",
            target,
            "fixture",
            repository,
        ],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    if host != "desktop":
        assert result.returncode != 0
        assert "Linux builds require a Linux builder" in result.stderr
        assert not calls.exists()
        return
    assert result.returncode == MOCK_EXIT_STATUS
    recorded = [json.loads(line) for line in calls.read_text().splitlines()]
    assert len(recorded) == 1
    arguments = recorded[0]
    assert arguments[:2] == ["python3", "/nix/store/mock-build_linux_package.py"]
    assert arguments[2] == f"{REPOSITORY_ROOT}/{repository}"
    assert arguments[3] == build_system
    assert arguments[4] == target
    assert arguments[5] == "fixture"
    assert Path(arguments[6]).parent == tmp_path / "state/nix-conf/builds"
    assert Path(arguments[6]).stat().st_mode & 0o077 == 0
    assert arguments[7] == "/nix/store/mock-build-package.nix"
