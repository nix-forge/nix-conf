"""Preserve recovery roots and active task executions across explicit retirement."""

from __future__ import annotations

import hashlib
import json
import os
import runpy
import time
from pathlib import Path
from types import SimpleNamespace
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from typing import Any

BASE = Path(__file__).parents[2] / "hosts/nixos/desktop/local/storage"
GENERATIONS = runpy.run_path(str(BASE / "retention.py"))
TASKS = runpy.run_path(str(BASE / "task_retention.py"))
DAY = 86400
CANDIDATE = 2
GENERATION_COUNT = 6


def generation_policy(tmp_path: Path) -> dict[str, Any]:
    """Create unrelated old/current/booted/pinned systems.

    Returns:
        A policy for disposable profile symlinks and a recording native command.

    """
    store = tmp_path / "store"
    store.mkdir()
    profile = tmp_path / "system"
    for number in range(1, 7):
        target = store / str(number)
        target.mkdir()
        link = tmp_path / f"system-{number}-link"
        link.symlink_to(target)
        old = time.time() - 30 * DAY
        os.utime(link, (old, old), follow_symlinks=False)
    profile.symlink_to(tmp_path / "system-6-link")
    (tmp_path / "current").symlink_to(store / "6")
    (tmp_path / "booted").symlink_to(store / "1")
    pins = tmp_path / "pins"
    pins.mkdir()
    (pins / "known-good").symlink_to(store / "3")
    (tmp_path / "bulk.lock").touch()
    command = tmp_path / "nix-env"
    command.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$0.args"\n', encoding="utf-8")
    command.chmod(0o700)
    return {
        "bulkLock": str(tmp_path / "bulk.lock"),
        "stateDirectory": str(tmp_path),
        "generations": {
            "profile": str(profile),
            "currentSystem": str(tmp_path / "current"),
            "bootedSystem": str(tmp_path / "booted"),
            "storeDirectory": str(store),
            "pinsDirectory": str(pins),
            "nixEnv": str(command),
            "keepCount": 2,
            "keepDays": 14,
        },
    }


def test_generation_union_preserves_booted_pinned_recent_and_latest(
    tmp_path: Path,
) -> None:
    """Retain each kind of recovery evidence even when it falls outside age/count."""
    cfg = generation_policy(tmp_path)
    young = tmp_path / "system-4-link"
    os.utime(young, None, follow_symlinks=False)
    result = GENERATIONS["plan"](cfg)
    assert result["candidates"] == [CANDIDATE]
    assert len(result["generations"]) == GENERATION_COUNT


def test_apply_refuses_profile_drift_before_native_deletion(tmp_path: Path) -> None:
    """A reviewed plan cannot silently authorize later source changes."""
    cfg = generation_policy(tmp_path)
    reviewed = GENERATIONS["plan"](cfg)
    os.utime(tmp_path / "system-2-link", None, follow_symlinks=False)
    with pytest.raises(ValueError, match="plan changed"):
        GENERATIONS["apply"](cfg, reviewed)
    assert not (tmp_path / "nix-env.args").exists()


def test_apply_deletes_only_exact_candidates_and_pins_booted(tmp_path: Path) -> None:
    """The native profile transaction receives generation IDs, never store deletion."""
    cfg = generation_policy(tmp_path)
    reviewed = GENERATIONS["plan"](cfg)
    result = GENERATIONS["apply"](cfg, reviewed)
    assert result["status"] == "retired"
    arguments = (tmp_path / "nix-env.args").read_text(encoding="utf-8").splitlines()
    assert arguments == [
        "--profile",
        str(tmp_path / "system"),
        "--delete-generations",
        "4",
        "2",
    ]
    assert (tmp_path / "pins/last-booted").resolve() == (tmp_path / "store/1")


def test_unsettled_activation_refuses_retirement(tmp_path: Path) -> None:
    """A switched profile with an old running system must wait for reconciliation."""
    cfg = generation_policy(tmp_path)
    current = tmp_path / "current"
    current.unlink()
    current.symlink_to(tmp_path / "store/5")
    with pytest.raises(ValueError, match="not settled"):
        GENERATIONS["plan"](cfg)


def test_active_profile_wrapper_matches_running_system(tmp_path: Path) -> None:
    """An activatable profile wrapper is settled when it runs the same system."""
    cfg = generation_policy(tmp_path)
    running = tmp_path / "store/6"
    (running / "bin").mkdir()
    wrapper = tmp_path / "store/activatable-system"
    wrapper.mkdir()
    (wrapper / "bin").symlink_to(running / "bin")
    generation = tmp_path / "system-6-link"
    generation.unlink()
    generation.symlink_to(wrapper)
    result = GENERATIONS["plan"](cfg)
    assert result["candidates"] == [4, CANDIDATE]
    assert str(running) in result["protectedTargets"]


def test_profile_wrapper_for_different_system_refuses_retirement(
    tmp_path: Path,
) -> None:
    """Recognizing wrappers must not admit a pending switch to different binaries."""
    cfg = generation_policy(tmp_path)
    (tmp_path / "store/5/bin").mkdir()
    (tmp_path / "store/6/bin").mkdir()
    wrapper = tmp_path / "store/activatable-system"
    wrapper.mkdir()
    (wrapper / "bin").symlink_to(tmp_path / "store/5/bin")
    generation = tmp_path / "system-6-link"
    generation.unlink()
    generation.symlink_to(wrapper)
    with pytest.raises(ValueError, match="not settled"):
        GENERATIONS["plan"](cfg)


def job_state(tmp_path: Path, owner: str = "finished-task") -> Path:
    """Write one preserved job and a pair of directly owned store roots.

    Returns:
        The disposable job directory.

    """
    directory = tmp_path / "jobs" / ("a" * 32)
    directory.mkdir(parents=True)
    (directory / "recipe.json").write_text(
        json.dumps({"owner": owner}), encoding="utf-8"
    )
    (directory / "result.json").write_text(
        json.dumps({"drained": True, "exitCode": 0}), encoding="utf-8"
    )
    for name in TASKS["ROOT_NAMES"]:
        (directory / name).symlink_to("/nix/store/" + "a" * 32 + "-fixture")
    return directory


def terminal() -> dict[str, Any]:
    """Return an independently drained native execution result.

    Returns:
        A synthetic public workstation-job status.

    """
    return {
        "nativeStatus": {"Done": {"Success": None}},
        "receipt": {"drained": True, "exitCode": 0},
    }


def test_task_dry_run_does_not_imply_completion(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A successful job is insufficient without explicit task completion."""
    directory = job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    result = TASKS["retire"](tmp_path, "finished-task", "fixture", None)
    assert not result["released"]
    assert (directory / "executor-root").is_symlink()


@pytest.mark.parametrize(
    "record",
    [
        {"nativeStatus": {"Running": {}}, "receipt": {"drained": True, "exitCode": 0}},
        {"nativeStatus": {"Done": {}}, "receipt": {"drained": False, "exitCode": 0}},
        {
            "nativeStatus": "missing-needs-reconciliation",
            "receipt": {"drained": True, "exitCode": 0},
        },
    ],
)
def test_task_refuses_active_or_ambiguous_execution(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, record: dict[str, Any]
) -> None:
    """Old age and terminal-looking receipts never override native uncertainty."""
    directory = job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: record
    )
    summary = tmp_path / "summary"
    summary.write_text("Preserved results", encoding="utf-8")
    with pytest.raises(ValueError, match="unresolved jobs"):
        TASKS["retire"](tmp_path, "finished-task", "fixture", summary)
    assert (directory / "executor-root").is_symlink()


def test_task_completion_releases_only_owned_roots_and_keeps_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Root retirement cannot remove job records, frozen source or another owner."""
    directory = job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    summary = tmp_path / "summary"
    summary.write_text("Preserved results", encoding="utf-8")
    result = TASKS["retire"](tmp_path, "finished-task", "fixture", summary)
    assert result["released"]
    assert not (directory / "executor-root").is_symlink()
    assert (directory / "recipe.json").exists()
    assert (directory / "result.json").exists()
    assert summary.exists()
    assert TASKS["retire"](tmp_path, "finished-task", "fixture", summary)["released"]


def cache_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Replace only provisioning proof; exercise the real ownership checks.

    Returns:
        A disposable root with the current user's private namespace.

    """
    import pwd  # ruff: ignore[import-outside-top-level] - The cache interface is Unix-only.

    root = tmp_path / "scratch"
    (root / pwd.getpwuid(os.getuid()).pw_name).mkdir(parents=True)
    monkeypatch.setitem(
        TASKS["cache_location"].__globals__, "verify_cache_root", lambda _: None
    )
    return root


def test_cache_creation_preserves_unknown_directories(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Only an owned marker allows reusing an existing cache directory."""
    root = cache_fixture(tmp_path, monkeypatch)
    first = TASKS["create_cache"](root, "finished-task")
    assert TASKS["create_cache"](root, "finished-task") == first
    marker = first.with_name("finished-task.owner.json")
    marker.unlink()
    with pytest.raises(ValueError, match="not an owned"):
        TASKS["create_cache"](root, "finished-task")
    assert first.exists()


def test_cache_results_must_be_preserved_outside_before_root_release(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A misplaced result cannot authorize partial cleanup of roots or cache."""
    root = cache_fixture(tmp_path, monkeypatch)
    cache = TASKS["create_cache"](root, "finished-task")
    summary = cache / "required-result"
    summary.write_text("Keep this", encoding="utf-8")
    directory = job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    with pytest.raises(ValueError, match="outside the cache"):
        TASKS["retire"](tmp_path, "finished-task", "fixture", summary, root)
    assert (directory / "executor-root").is_symlink()
    assert summary.exists()


def test_explicit_completed_cache_cleanup_keeps_external_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Remove only the named cache after native job completion is proven."""
    root = cache_fixture(tmp_path, monkeypatch)
    cache = TASKS["create_cache"](root, "finished-task")
    (cache / "regenerable-object").write_text("Rebuild me", encoding="utf-8")
    package = cache / "readonly-package"
    package.mkdir()
    payload = package / "object"
    payload.write_text("Regenerable build output", encoding="utf-8")
    payload.chmod(0o444)
    package.chmod(0o555)
    job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    summary = tmp_path / "preserved-result"
    summary.write_text("Durable evidence", encoding="utf-8")
    assert TASKS["retire"](tmp_path, "finished-task", "fixture", summary, root)[
        "released"
    ]
    assert not cache.exists()
    assert summary.exists()


def test_booted_activatable_wrapper_retains_its_generation(tmp_path: Path) -> None:
    """A wrapper's store target can differ from the raw booted system target."""
    cfg = generation_policy(tmp_path)
    actual_bin = tmp_path / "store/1/bin"
    actual_bin.mkdir()
    wrapper = tmp_path / "store/wrapped-system"
    wrapper.mkdir()
    (wrapper / "bin").symlink_to(actual_bin)
    generation = tmp_path / "system-1-link"
    generation.unlink()
    generation.symlink_to(wrapper)
    old = time.time() - 30 * DAY
    os.utime(generation, (old, old), follow_symlinks=False)
    assert 1 not in GENERATIONS["plan"](cfg)["candidates"]


def test_preview_retirement_preserves_operator_changes_and_pin(tmp_path: Path) -> None:
    """Only exact recorded overrides may be removed during normal activation."""
    helper = runpy.run_path(
        str(
            Path(__file__).parents[2]
            / "hosts/nixos/desktop/local/storage/scripts/retire-preview.py"
        )
    )
    override = tmp_path / "override.conf"
    override.write_text("owned")
    target = tmp_path / "rollout"
    target.mkdir()
    pin = tmp_path / "pin"
    pin.symlink_to(target)
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps({
            "pin": str(pin),
            "target": str(target),
            "overrides": [
                {"path": str(override), "sha256": hashlib.sha256(b"owned").hexdigest()}
            ],
        })
    )
    override.write_text("operator-change")
    assert not helper["retire"](manifest)
    assert pin.is_symlink()
    assert override.read_text() == "operator-change"
    override.write_text("owned")
    assert helper["retire"](manifest)
    assert not override.exists()
    assert not pin.is_symlink()
    assert manifest.with_suffix(".retired.json").exists()


def test_empty_legacy_submission_is_preserved_but_unknown_state_refuses(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An empty aborted submission cannot block another task's safe retirement."""
    directory = job_state(tmp_path)
    abandoned = tmp_path / "jobs" / ("b" * 32)
    abandoned.mkdir()
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    plan = TASKS["retire"](tmp_path, "finished-task", "fixture", None)
    assert len(plan["jobs"]) == 1
    assert abandoned.is_dir()
    (abandoned / "unknown-state").write_text("preserve", encoding="utf-8")
    with pytest.raises(FileNotFoundError):
        TASKS["retire"](tmp_path, "finished-task", "fixture", None)
    assert (directory / "executor-root").is_symlink()
    assert (abandoned / "unknown-state").read_text(encoding="utf-8") == "preserve"


def test_foreign_cache_directory_refuses_before_job_root_release(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Only the task owner's directories can be made writable for retirement."""
    root = cache_fixture(tmp_path, monkeypatch)
    cache = TASKS["create_cache"](root, "finished-task")
    foreign = cache / "other-identity"
    foreign.mkdir()
    directory = job_state(tmp_path)
    monkeypatch.setitem(
        TASKS["retirement_plan"].__globals__, "inspect_job", lambda *_: terminal()
    )
    original = Path.stat
    monkeypatch.setattr(
        Path,
        "stat",
        lambda self, *args, **kwargs: (
            SimpleNamespace(st_uid=os.getuid() + 1, st_ino=1)
            if self == foreign
            else original(self, *args, **kwargs)
        ),
    )
    evidence = tmp_path / "preserved-result"
    evidence.write_text("Preserved evidence", encoding="utf-8")
    with pytest.raises(ValueError, match="another identity"):
        TASKS["retire"](tmp_path, "finished-task", "fixture", evidence, root)
    assert (directory / "executor-root").is_symlink()
    assert foreign.exists()
