"""Execute actual upstream and repaired permission checks with OS-call adapters."""

from __future__ import annotations

import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Mocked command boundaries.
from dataclasses import dataclass
from pathlib import Path

import pytest

pytestmark = pytest.mark.nix_integration


@dataclass(frozen=True)
class ConsentProbe:
    """Describe one permission-check environment without changing shell inputs."""

    kind: str
    touch: str
    manager: str = "Aqua"
    dry_run: bool = False
    migration: bool = False


@pytest.fixture
def fragments() -> dict[str, dict[str, str]]:
    """Read checks evaluated from the real pinned modules by Nix.

    Returns:
        Both original and repaired activation fragments.

    """
    return json.loads(
        Path(os.environ["APP_MANAGEMENT_FRAGMENTS"]).read_text(encoding="utf-8")
    )


def exercise(
    directory: Path,
    script: str,
    *,
    probe: ConsentProbe,
) -> tuple[subprocess.CompletedProcess[str], int, int]:
    """Run real checks while replacing only their native command boundaries.

    Returns:
        Raw exit/output and counts of permission probes and resets.

    """
    directory.mkdir()
    app = directory / "apps" / "Fixture.app"
    app.mkdir(parents=True)
    if probe.migration:
        (directory / "apps").rename(directory / "old-apps")
        (directory / "apps").symlink_to("old-apps", target_is_directory=True)
    adapter = directory / "touch-adapter"
    adapter.write_text(
        f"#!{os.environ['APP_MANAGEMENT_BASH']}\nset -eu\n"
        'n=0; [[ ! -f "$PWD/touch-count" ]] || read -r n < "$PWD/touch-count"\n'
        'n=$((n+1)); printf "%s\\n" "$n" > "$PWD/touch-count"\n'
        '[[ "$TOUCH_RESULT" != always ]] || exit 1\n'
        '[[ "$TOUCH_RESULT" != first || "$n" != 1 ]]\n'
    )
    adapter.chmod(0o700)
    reset = directory / "tccutil"
    reset.write_text(
        f'#!{os.environ["APP_MANAGEMENT_BASH"]}\nprintf "reset\\n" >> "$PWD/reset-count"\n'
    )
    reset.chmod(0o700)
    launch = directory / "launchctl"
    launch.write_text(
        f'#!{os.environ["APP_MANAGEMENT_BASH"]}\nprintf "%s\\n" "$MANAGER"\n'
    )
    launch.chmod(0o700)
    if probe.kind == "root":
        needle = r"/Applications/Nix\ Apps/*.app"
        assert script.count(needle) == 1
        script = script.replace(needle, '"$PWD/apps/"*.app')
        script = script.replace("if ! touch ", f'if ! "{adapter}" ')
    else:
        assert script.count("/usr/bin/touch") == 1
        assert script.count("/bin/launchctl") == 1
        script = script.replace("/usr/bin/touch", str(adapter))
        script = script.replace("/bin/launchctl", str(launch))
        script = script.replace("/usr/bin/tccutil", str(reset))
    preamble = 'run() { if [[ "$DRY_RUN" == 1 ]]; then return 0; else "$@"; fi; }\n'
    environment = os.environ | {
        "PATH": str(directory) + os.pathsep + os.environ["PATH"],
        "TOUCH_RESULT": probe.touch,
        "MANAGER": probe.manager,
        "DRY_RUN": str(int(probe.dry_run)),
    }
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Pinned Bash and evaluated repository fragments with isolated command adapters.
        [os.environ["APP_MANAGEMENT_BASH"], "-eu", "-c", preamble + script],
        cwd=directory,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
        shell=False,
    )
    count = directory / "touch-count"
    resets = directory / "reset-count"
    return (
        result,
        int(count.read_text(encoding="utf-8")) if count.exists() else 0,
        len(resets.read_text(encoding="utf-8").splitlines()) if resets.exists() else 0,
    )


@pytest.mark.parametrize("kind", ["root", "home"])
@pytest.mark.parametrize(
    "scenario",
    [("never", 0, 1), ("always", 1, 2), ("first", 0, 2)],
    ids=["never-0-1", "always-1-2", "first-0-2"],
)
def test_native_consent_keeps_checks_without_reset(
    fragments: dict[str, dict[str, str]],
    tmp_path: Path,
    kind: str,
    scenario: tuple[str, int, int],
) -> None:
    """Success, persistent denial and a transient denial retain probe semantics."""
    touch, expected_exit, expected_calls = scenario
    result, calls, resets = exercise(
        tmp_path / "fixed",
        fragments["fixed"][kind],
        probe=ConsentProbe(kind=kind, touch=touch),
    )
    assert result.returncode == expected_exit, result.stderr
    assert calls == expected_calls
    assert resets == 0
    if expected_exit:
        assert "permissions were left unchanged" in result.stderr
        assert "Privacy & Security > App Management" in result.stderr
    old, old_calls, old_resets = exercise(
        tmp_path / "baseline",
        fragments["baseline"][kind],
        probe=ConsentProbe(kind=kind, touch=touch),
    )
    assert old.returncode == expected_exit
    assert old_calls == calls
    assert old_resets == int(touch != "never")


@pytest.mark.parametrize("kind", ["root", "home"])
def test_remote_denial_never_resets_or_copies(
    fragments: dict[str, dict[str, str]],
    tmp_path: Path,
    kind: str,
) -> None:
    """Non-Aqua denial remains fail-closed before any copy operation."""
    result, calls, resets = exercise(
        tmp_path / "remote",
        fragments["fixed"][kind],
        probe=ConsentProbe(kind=kind, touch="always", manager="Background"),
    )
    assert result.returncode == 1
    assert calls == 1
    assert resets == 0
    assert "aborting activation" in result.stderr


def test_home_dry_run_does_not_mutate_permissions(
    fragments: dict[str, dict[str, str]],
    tmp_path: Path,
) -> None:
    """Home Manager's real run adapter remains respected by the check."""
    result, calls, resets = exercise(
        tmp_path / "dry-run",
        fragments["fixed"]["home"],
        probe=ConsentProbe(kind="home", touch="always", dry_run=True),
    )
    assert (result.returncode, calls, resets) == (0, 0, 0)


def test_home_link_migration_keeps_original_exception(
    fragments: dict[str, dict[str, str]],
    tmp_path: Path,
) -> None:
    """The upstream symlink migration still bypasses its impossible probe."""
    result, calls, resets = exercise(
        tmp_path / "migration",
        fragments["fixed"]["home"],
        probe=ConsentProbe(kind="home", touch="always", migration=True),
    )
    assert (result.returncode, calls, resets) == (0, 0, 0)


@pytest.mark.parametrize("kind", ["root", "home"])
def test_only_reset_and_consent_text_change(
    fragments: dict[str, dict[str, str]],
    kind: str,
) -> None:
    """All remaining check, retry, failure and migration code stays identical."""
    permitted = (
        "# The TCC service required",
        "# and we can reset it",
        "# App Management consent is user-owned;",
        "tccutil reset SystemPolicyAppBundles",
        "requires permission to update your apps, please accept the notification",
        "and grant the permission for your terminal emulator in System Settings.",
        "could not update your apps; App Management permissions were left unchanged.",
        "In System Settings > Privacy & Security > App Management, grant access",
    )
    old = fragments["baseline"][kind]
    fixed = fragments["fixed"][kind]
    assert "tccutil reset" in old
    assert "tccutil reset" not in fixed
    assert "if ! ensureAppManagement; then" in fixed
    assert [
        line for line in old.splitlines() if not any(word in line for word in permitted)
    ] == [
        line
        for line in fixed.splitlines()
        if not any(word in line for word in permitted)
    ]
