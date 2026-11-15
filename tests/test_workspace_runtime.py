"""Check the private configuration boundary of the generic service dispatcher."""

import json
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed interpreter fixture
import sys
from pathlib import Path

RUNNER = (
    Path(__file__).resolve().parents[1]
    / "homes/desktop/local/workspace-services/runner.py"
)
RETIRE_PREVIEW = RUNNER.parent / "scripts/retire-unit-preview.sh"


def _retire_preview(config: Path, state: Path) -> None:
    """Invoke the same cleanup command as a managed activation."""
    bash = shutil.which("bash")
    assert bash is not None
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed repair cleanup script
        [bash, str(RETIRE_PREVIEW), str(config), str(state)], check=True
    )


def test_dispatcher_rejects_exposed_configuration(tmp_path: Path) -> None:
    """A world-readable runtime file cannot select an executable."""
    config = tmp_path / "custom config %literal$dollar/workspace-services/private.json"
    config.parent.mkdir(parents=True)
    config.write_text("{}")
    config.chmod(0o644)
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed interpreter fixture
        [sys.executable, "-I", str(RUNNER), str(config)],
        env={**os.environ, "HOME": str(tmp_path)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert "owner-only" in result.stderr


def test_dispatcher_rejects_configuration_symlink(tmp_path: Path) -> None:
    """A replaced final pathname cannot redirect private command selection."""
    config = tmp_path / "custom config %literal$dollar/workspace-services/private.json"
    config.parent.mkdir(parents=True)
    target = tmp_path / "settings"
    target.write_text("{}")
    target.chmod(0o600)
    config.symlink_to(target)
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed interpreter fixture
        [sys.executable, "-I", str(RUNNER), str(config)],
        env={**os.environ, "HOME": str(tmp_path)},
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0


def test_dispatcher_runs_private_command_without_embedded_source(
    tmp_path: Path,
) -> None:
    """Application selection comes from private state, not the public package."""
    config = tmp_path / "custom config %literal$dollar/workspace-services/private.json"
    config.parent.mkdir(parents=True)
    config.write_text(
        json.dumps({
            "source_directory": str(tmp_path),
            "state_directory": str(tmp_path / "state"),
            "cli": [
                sys.executable,
                str(
                    Path(__file__).with_name("fixtures")
                    / "report_workspace_environment.py"
                ),
            ],
        })
    )
    config.chmod(0o600)
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed interpreter fixture
        [sys.executable, "-I", str(RUNNER), str(config)],
        env={**os.environ, "HOME": str(tmp_path)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        str(tmp_path / "state"),
        str(tmp_path),
        str(tmp_path),
    ]


def test_retire_preview_removes_only_the_owned_repair(tmp_path: Path) -> None:
    """A normal activation retires the exact preview and matching drop-ins."""
    config = tmp_path / "config with spaces"
    state = tmp_path / "state"
    preview = config / "systemd/user.control/workspace-edge.service"
    preview.parent.mkdir(parents=True)
    preview.symlink_to(state / "workspace-services/unit-preview/workspace-edge.service")
    for name in ("api", "worker", "dashboard", "edge"):
        override = (
            config / f"systemd/user/workspace-{name}.service.d/90-runtime-recovery.conf"
        )
        override.parent.mkdir(parents=True)
        override.write_text("[Service]\nPrivateTmp=no\n")
    _retire_preview(config, state)
    assert not preview.is_symlink()
    assert not list(config.glob("systemd/user/*.service.d/90-runtime-recovery.conf"))


def test_retire_preview_preserves_unrecognized_overrides(tmp_path: Path) -> None:
    """Changed files and foreign symlinks remain under their existing owner."""
    config = tmp_path / "config"
    state = tmp_path / "state"
    preview = config / "systemd/user.control/workspace-edge.service"
    preview.parent.mkdir(parents=True)
    preview.symlink_to(tmp_path / "someone-elses-unit")
    override = config / "systemd/user/workspace-api.service.d/90-runtime-recovery.conf"
    override.parent.mkdir(parents=True)
    override.write_text("[Service]\nPrivateTmp=yes\n")
    linked = config / "systemd/user/workspace-worker.service.d/90-runtime-recovery.conf"
    linked.parent.mkdir(parents=True)
    linked.symlink_to(override)
    _retire_preview(config, state)
    assert preview.readlink() == tmp_path / "someone-elses-unit"
    assert override.read_text() == "[Service]\nPrivateTmp=yes\n"
    assert linked.is_symlink()


def test_retire_preview_is_safe_when_no_repair_exists(tmp_path: Path) -> None:
    """Ordinary installations and repeated activation require no preview."""
    for _ in range(2):
        _retire_preview(tmp_path / "config", tmp_path / "state")
