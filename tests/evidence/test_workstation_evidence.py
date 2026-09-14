"""Check evidence provenance and failure semantics using disposable real commands."""

from __future__ import annotations

import argparse
import copy
import json
import os
import runpy
import subprocess
import sys
from pathlib import Path

import pytest

TOOL_PATH = Path(__file__).resolve().parents[2] / "scripts/workstation_evidence.py"
TOOL = runpy.run_path(str(TOOL_PATH))
GLOBALS = TOOL["capture"].__globals__


@pytest.fixture
def repository(tmp_path: Path) -> Path:
    """Create isolated Git history without inheriting signing or hooks.

    Returns:
        The disposable repository.

    """
    root = tmp_path / "repo"
    root.mkdir()
    env = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    subprocess.run(["git", "init", str(root)], env=env, check=True, capture_output=True)
    (root / "flake.lock").write_text("{}\n")
    subprocess.run(["git", "-C", str(root), "add", "."], env=env, check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.hooksPath=/dev/null",
            "commit",
            "-m",
            "fixture",
        ],
        env=env,
        check=True,
        capture_output=True,
    )
    return root


def arguments(
    root: Path, output: Path, command: list[str], **changes: object
) -> argparse.Namespace:
    """Construct the same explicit options used by the capture CLI.

    Returns:
        The parsed-equivalent capture options.

    """
    values = {
        "source": root,
        "output": output,
        "command": command,
        "phase": "evaluation",
        "target": "fixture",
        "check": "fixture-command",
        "runs": 1,
        "timeout": 10,
        "cache_condition": "warm",
        "installable": None,
        "build_receipt": None,
    }
    values.update(changes)
    return argparse.Namespace(**values)


def test_source_tracks_dirty_and_intent_to_add_but_ignores_untracked(
    repository: Path,
) -> None:
    """Source tracks dirty and intent to add but ignores untracked."""
    original = TOOL["source_identity"](repository)
    extra = repository / "new.nix"
    extra.write_text("{}")
    assert TOOL["source_identity"](repository) == original
    subprocess.run(["git", "-C", str(repository), "add", "-N", "new.nix"], check=True)
    changed = TOOL["source_identity"](repository)
    assert changed["tree_sha256"] != original["tree_sha256"]
    assert changed["dirty"]
    (repository / "flake.lock").write_text('{"changed": true}')
    assert TOOL["source_identity"](repository)["lockfiles"] != original["lockfiles"]


def test_successful_command_writes_private_evidence(
    repository: Path, tmp_path: Path
) -> None:
    """Successful command writes private evidence."""
    receipt, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "print('fixture output')"],
        )
    )
    assert record["status"] == "passed"
    assert record["measurements"][0]["elapsed_seconds"] > 0
    assert record["measurements"][0]["peak_rss_kib"] > 0
    assert receipt.stat().st_mode & 0o777 == 0o600
    assert (
        "fixture output"
        in (receipt.parent / record["measurements"][0]["log"]).read_text()
    )
    assert json.loads(receipt.read_text())["source"] == TOOL["source_identity"](
        repository
    )


def test_failure_is_not_hidden_by_partial_benchmark(
    repository: Path, tmp_path: Path
) -> None:
    """Failure is not hidden by partial benchmark."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "raise SystemExit(7)"],
            runs=3,
        )
    )
    assert record["status"] == "failed"
    assert len(record["measurements"]) == 1
    assert record["measurements"][0]["exit_code"] == 7


def test_timeout_terminates_command_and_records_failure(
    repository: Path, tmp_path: Path
) -> None:
    """Timeout terminates command and records failure."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "import time; time.sleep(30)"],
            timeout=0.05,
        )
    )
    assert record["status"] == "failed"
    assert record["measurements"][0]["timed_out"]
    assert record["measurements"][0]["elapsed_seconds"] < 5


def test_source_change_invalidates_success(repository: Path, tmp_path: Path) -> None:
    """Source change invalidates success."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [
                sys.executable,
                "-c",
                "from pathlib import Path; Path('flake.lock').write_text('changed')",
            ],
        )
    )
    assert record["status"] == "invalid"
    assert record["source_after"] != record["source"]


def test_runtime_requires_matching_build_evidence(
    repository: Path, tmp_path: Path
) -> None:
    """Runtime requires matching build evidence."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "raise SystemExit(99)"],
            phase="runtime",
        )
    )
    assert record["status"] == "invalid"
    assert record["measurements"] == []


def test_runtime_checks_real_symlink_target(tmp_path: Path) -> None:
    """Runtime checks real symlink target."""
    old, candidate, link = (tmp_path / name for name in ("old", "candidate", "current"))
    old.mkdir()
    candidate.mkdir()
    link.symlink_to(old)
    assert not TOOL["runtime_matches"](str(candidate), link)
    link.unlink()
    link.symlink_to(candidate)
    assert TOOL["runtime_matches"](str(candidate), link)


def test_evidence_cannot_pollute_public_source(repository: Path) -> None:
    """Evidence cannot pollute public source."""
    with pytest.raises(ValueError, match="outside"):
        TOOL["private_directory"](repository / "evidence", repository)


def benchmark(samples: list[int]) -> dict:
    """Create independent measurements with the public receipt fields.

    Returns:
        An independently specified comparison fixture.

    """
    return {
        "target": "fixture",
        "check": "eval",
        "phase": "evaluation",
        "system": "x86_64-linux",
        "cache_condition": "warm",
        "schema": 1,
        "kind": "benchmark" if len(samples) > 1 else "check",
        "date": "2026-01-01T00:00:00+00:00",
        "finished": "2026-01-01T00:01:00+00:00",
        "source": {
            "revision": "a" * 40,
            "tree_sha256": "b" * 64,
            "dirty": False,
            "lockfiles": {},
            "submodules": {},
        },
        "expected_runs": len(samples),
        "command_sha256": "c" * 64,
        "environment_sha256": "d" * 64,
        "nix_configuration": {"status": "captured", "sha256": "e" * 64},
        "status": "passed",
        "measurements": [
            {
                "elapsed_seconds": value,
                "peak_rss_kib": value * 10,
                "user_seconds": 0,
                "system_seconds": 0,
                "exit_code": 0,
                "timed_out": False,
                "descendants_remained": False,
                "log": f"trial-{index}.log",
            }
            for index, value in enumerate(samples)
        ],
    }


def test_comparison_reports_spread_and_regression() -> None:
    """Comparison reports spread and regression."""
    result = TOOL["compare"](benchmark([10, 11, 12]), benchmark([14, 15, 16]), 10)
    assert result["status"] == "failed"
    metric = result["metrics"]["elapsed_seconds"]
    assert metric["baseline_median"] == 11
    assert metric["candidate_median"] == 15
    assert not metric["ranges_overlap"]


@pytest.mark.parametrize(
    "change",
    [
        {"status": "failed", "reason": "Fixture failure"},
        {"cache_condition": "cold"},
        {"system": "aarch64-darwin"},
        {"measurements": []},
    ],
)
def test_incomparable_or_failed_benchmarks_are_rejected(change: dict) -> None:
    """Incomparable or failed benchmarks are rejected."""
    invalid = benchmark([10, 11, 12]) | change
    with pytest.raises(ValueError, match=r"differ|Failed|complete"):
        TOOL["compare"](benchmark([10, 11, 12]), invalid, 10)


def test_coverage_uses_latest_matching_source_not_old_success(repository: Path) -> None:
    """Coverage uses latest matching source not old success."""
    check = {
        "target": "fixture",
        "check": "build",
        "phase": "build",
        "system": "x86_64-linux",
    }
    manifest = {"schema": 1, "checks": [check]}
    passed = (
        benchmark([1])
        | check
        | {
            "date": "2026-01-01T00:00:00+00:00",
            "status": "passed",
            "source": TOOL["source_identity"](repository),
        }
    )
    failed = passed | {
        "date": "2026-01-01T00:00:01+00:00",
        "finished": "2026-01-01T00:02:00+00:00",
        "status": "failed",
        "reason": "Fixture failure",
    }
    result = TOOL["coverage"](repository, manifest, [passed, failed])
    assert result["status"] == "incomplete"
    assert result["checks"][0]["status"] == "failed"
    (repository / "flake.lock").write_text("changed")
    result = TOOL["coverage"](repository, manifest, [passed])
    assert result["checks"][0]["status"] == "missing"


def test_atomic_receipt_does_not_overwrite_existing(tmp_path: Path) -> None:
    """Atomic receipt does not overwrite existing."""
    receipt = tmp_path / "record.json"
    TOOL["write_json"](receipt, {"status": "failed"})
    with pytest.raises(FileExistsError):
        TOOL["write_json"](receipt, {"status": "passed"})
    assert json.loads(receipt.read_text()) == {"status": "failed"}
    assert len(list(tmp_path.iterdir())) == 1


def git_fixture(root: Path, *args: str) -> bytes:
    """Run disposable Git operations without hooks, signing or inherited overrides.

    Returns:
        The fixture command's standard output.

    """
    env = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
    return subprocess.check_output(
        [
            "git",
            "-C",
            str(root),
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "protocol.file.allow=always",
            *args,
        ],
        env=env,
    )


@pytest.fixture
def submodule_repository(repository: Path, tmp_path: Path) -> Path:
    """Add a real initialized local submodule with a tracked lockfile.

    Returns:
        The root repository containing the initialized submodule.

    """
    upstream = tmp_path / "upstream"
    upstream.mkdir()
    git_fixture(upstream, "init")
    (upstream / "flake.lock").write_text("{}\n")
    git_fixture(upstream, "add", ".")
    git_fixture(upstream, "commit", "-m", "fixture")
    git_fixture(repository, "submodule", "add", str(upstream), "child")
    git_fixture(repository, "commit", "-am", "submodule fixture")
    return repository


def test_submodule_changes_and_untracked_filtering(submodule_repository: Path) -> None:
    """Track submodule edits and lockfiles while ignoring their untracked files."""
    root = submodule_repository
    before = TOOL["source_identity"](root)
    (root / "child/untracked").write_text("ignored")
    assert TOOL["source_identity"](root) == before
    (root / "child/flake.lock").write_text('{"changed": true}')
    after = TOOL["source_identity"](root)
    assert after["tree_sha256"] != before["tree_sha256"]
    assert after["submodules"]["child"]["dirty"]
    assert (
        after["submodules"]["child"]["lockfiles"]
        != before["submodules"]["child"]["lockfiles"]
    )
    TOOL["validate_source"](after)


def test_unavailable_submodule_fails_closed(submodule_repository: Path) -> None:
    """Reject unavailable submodules instead of accidentally reading the parent."""
    git_fixture(submodule_repository, "submodule", "deinit", "--force", "child")
    with pytest.raises(ValueError, match="Initialize"):
        TOOL["source_identity"](submodule_repository)


def test_source_distinguishes_symlink_mode_and_deletion(repository: Path) -> None:
    """Treat filesystem kind, executable mode and deletion as distinct sources."""
    path = repository / "tracked"
    path.write_text("contents")
    git_fixture(repository, "add", "tracked")
    original = TOOL["source_identity"](repository)
    path.chmod(0o755)
    executable = TOOL["source_identity"](repository)
    path.unlink()
    absent = TOOL["source_identity"](repository)
    path.symlink_to("flake.lock")
    link = TOOL["source_identity"](repository)
    assert (
        len({item["tree_sha256"] for item in (original, executable, absent, link)}) == 4
    )


@pytest.mark.nix_daemon
def test_identity_matches_nix_git_filtering(submodule_repository: Path) -> None:
    """Use a dependency-free flake to compare Nix's real Git source selection."""
    root = submodule_repository
    (root / "flake.lock").unlink()
    (root / "flake.nix").write_text("""{
        inputs.self.submodules = true;
        outputs = { self }: { observed = {
            tracked = builtins.pathExists (self + "/added");
            hidden = builtins.pathExists (self + "/untracked");
            childHidden = builtins.pathExists (self + "/child/untracked");
            childLock = builtins.readFile (self + "/child/flake.lock");
        }; };
    }""")
    git_fixture(root, "add", "-A")
    git_fixture(root, "commit", "-m", "dependency-free filtering fixture")
    before = TOOL["source_identity"](root)
    (root / "untracked").write_text("ignored")
    (root / "child/untracked").write_text("ignored")
    assert TOOL["source_identity"](root) == before
    (root / "added").write_text("candidate")
    git_fixture(root, "add", "-N", "added")
    (root / "child/flake.lock").write_text("dirty child\n")
    observed = json.loads(
        subprocess.check_output(
            [
                "nix",
                "--extra-experimental-features",
                "nix-command flakes",
                "eval",
                "--json",
                "--no-write-lock-file",
                f"{root}#observed",
            ],
            text=True,
            timeout=60,
        )
    )
    assert observed == {
        "tracked": True,
        "hidden": False,
        "childHidden": False,
        "childLock": "dirty child\n",
    }
    assert TOOL["source_identity"](root)["tree_sha256"] != before["tree_sha256"]


def test_background_child_is_rejected_and_killed(
    repository: Path, tmp_path: Path
) -> None:
    """A successful parent cannot leave work running outside its recorded duration."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [
                sys.executable,
                "-c",
                "import subprocess,sys; p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); print(p.pid,flush=True)",
            ],
            timeout=0.2,
        )
    )
    sample = record["measurements"][0]
    assert record["status"] == "failed"
    assert sample["descendants_remained"]
    pid = int((tmp_path / "evidence" / sample["log"]).read_text())
    # A killed orphan can remain a zombie until init reaps it; it cannot do work.
    result = subprocess.run(
        ["ps", "-o", "stat=", "-p", str(pid)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0 or result.stdout.strip().startswith("Z")


@pytest.mark.parametrize(
    "change",
    [
        {"elapsed_seconds": -1},
        {"elapsed_seconds": 10**1000},
        {"peak_rss_kib": float("nan")},
        {"elapsed_seconds": float("inf")},
        {"exit_code": False},
        {"exit_code": 7},
        {"timed_out": True},
        {"descendants_remained": True},
        {"user_seconds": -1},
        {"log": "../outside.log"},
    ],
)
def test_passed_receipt_rejects_invalid_sample(change: dict) -> None:
    """Invalid outcomes and impossible numbers cannot support a passed report."""
    candidate = benchmark([1, 2, 3])
    candidate["measurements"][0].update(change)
    with pytest.raises(ValueError, match="measurements"):
        TOOL["compare"](benchmark([1, 2, 3]), candidate, 10)


@pytest.mark.parametrize(
    "change",
    [
        {"source": {}},
        {"source": {"revision": "a", "tree_sha256": []}},
        {"schema": True},
        {"status": []},
        {"command_sha256": "short"},
        {"date": "2026-01-01"},
        {"date": "9999-01-01T00:00:00+00:00"},
        {"expected_runs": True},
        {"expected_runs": 4},
        {"phase": "unknown"},
    ],
)
def test_malformed_receipts_fail_with_validation_error(change: dict) -> None:
    """Malformed envelopes produce validation errors instead of success or crashes."""
    with pytest.raises(ValueError, match=r"Evidence|Evidence dates|Passed|Unsupported"):
        TOOL["validate_receipt"](benchmark([1, 2, 3]) | change)


@pytest.mark.parametrize("payload", [[], None, {}, {"schema": 1, "status": "passed"}])
def test_incomplete_json_receipt_rejected(tmp_path: Path, payload: object) -> None:
    """Reject receipts that were previously accepted after only schema/status checks."""
    path = tmp_path / "record.json"
    path.write_text(json.dumps(payload))
    with pytest.raises(ValueError, match="Evidence"):
        TOOL["read_receipt"](path)


@pytest.mark.parametrize("budget", [float("nan"), float("inf"), -1])
def test_invalid_comparison_budget_rejected(budget: float) -> None:
    """Reject nonfinite and negative budgets."""
    with pytest.raises(ValueError, match="budget"):
        TOOL["compare"](benchmark([1, 2, 3]), benchmark([1, 2, 3]), budget)


def test_comparison_requires_environment_and_explicit_cache() -> None:
    """Matching architecture alone cannot establish a comparable benchmark."""
    base = benchmark([1, 2, 3])
    with pytest.raises(ValueError, match="environment"):
        TOOL["compare"](base, base | {"environment_sha256": "e" * 64}, 10)
    with pytest.raises(ValueError, match="explicit"):
        TOOL["compare"](base | {"cache_condition": "unspecified"}, base, 10)
    candidate = copy.deepcopy(base)
    candidate["source"]["revision"] = "f" * 40
    compared = TOOL["compare"](base, candidate, 10)
    assert compared["baseline_source"] == base["source"]
    assert compared["candidate_source"] == candidate["source"]
    assert compared["workload"]["environment_sha256"] == base["environment_sha256"]


@pytest.fixture
def candidate_generation(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Supply a real existing store output and an isolated active-generation link.

    Returns:
        The disposable active-generation symlink used by the runtime checks.

    """
    output = next(
        parent
        for parent in Path(sys.executable).resolve().parents
        if parent.parent == Path("/nix/store")
    )
    active = tmp_path / "current-system"
    active.symlink_to(output)
    monkeypatch.setitem(GLOBALS, "ACTIVE_SYSTEM", active)
    monkeypatch.setitem(
        GLOBALS,
        "nix_output",
        lambda _root, *args: (
            '{"cores": {"value": "2"}}' if args[0] == "config" else str(output)
        ),
    )
    return active


def build_receipt(repository: Path, tmp_path: Path) -> Path:
    """Capture a successful candidate build through the isolated Nix adapter.

    Returns:
        The complete build receipt, with measured command execution.

    """
    receipt, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "pass"],
            phase="build",
            check="full-system",
            installable="nixosConfigurations.fixture.config.system.build.toplevel",
        )
    )
    assert record["status"] == "passed"
    return receipt


@pytest.mark.parametrize(
    "phase", ["runtime", "recovery", "activation", "dry-activation"]
)
def test_system_phases_reuse_matching_build(
    repository: Path, tmp_path: Path, candidate_generation: Path, phase: str
) -> None:
    """Successful dependent phases carry the exact prior build and output identity."""
    built = build_receipt(repository, tmp_path)
    receipt, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "pass"],
            phase=phase,
            build_receipt=built,
        )
    )
    assert record["status"] == "passed"
    assert record["system_path"] == str(candidate_generation.resolve())
    assert record["build_receipt_sha256"] == TOOL["digest"](built.read_bytes())
    assert record["active_system_before"] == str(candidate_generation.resolve())
    assert record["active_system_after"] == str(candidate_generation.resolve())
    assert TOOL["read_receipt"](receipt) == record


@pytest.mark.parametrize(
    "phase", ["runtime", "recovery", "activation", "dry-activation"]
)
def test_system_transition_away_from_candidate_is_invalid(
    repository: Path, tmp_path: Path, candidate_generation: Path, phase: str
) -> None:
    """Detect a changed active generation even when the check command succeeds."""
    built = build_receipt(repository, tmp_path)
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [
                sys.executable,
                "-c",
                "from pathlib import Path; import sys; Path(sys.argv[1]).unlink()",
                str(candidate_generation),
            ],
            phase=phase,
            build_receipt=built,
        )
    )
    assert record["status"] == "invalid"
    assert "generation" in record["reason"]


def test_build_receipt_cannot_bind_changed_source(
    repository: Path, tmp_path: Path, candidate_generation: Path
) -> None:
    """Reject stale build provenance before running the dependent command."""
    assert candidate_generation.exists()
    built = build_receipt(repository, tmp_path)
    (repository / "flake.lock").write_text("changed")
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "raise SystemExit(99)"],
            phase="runtime",
            build_receipt=built,
        )
    )
    assert record["status"] == "invalid"
    assert record["measurements"] == []


@pytest.mark.parametrize("failure_phase", ["eval", "path-info"])
def test_verification_timeout_preserves_failed_receipt(
    repository: Path,
    tmp_path: Path,
    candidate_generation: Path,
    monkeypatch: pytest.MonkeyPatch,
    failure_phase: str,
) -> None:
    """Preserve candidate evaluation and post-command realization timeouts."""

    def verification(_root: Path, *args: str) -> str:
        if args[0] == failure_phase:
            raise subprocess.TimeoutExpired(["nix", *args], 120)
        return str(candidate_generation.resolve())

    monkeypatch.setitem(GLOBALS, "nix_output", verification)
    receipt, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "pass"],
            phase="build",
            check="full-system",
            installable="packages.fixture",
        )
    )
    assert record["status"] == "failed"
    assert "TimeoutExpired" in record["reason"]
    assert len(record["measurements"]) == (0 if failure_phase == "eval" else 1)
    assert TOOL["read_receipt"](receipt) == record


def test_full_build_without_output_cannot_pass(
    repository: Path, tmp_path: Path
) -> None:
    """Require candidate realization evidence even for a successful shell command."""
    _, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "pass"],
            phase="build",
            check="full-system",
        )
    )
    assert record["status"] == "invalid"
    assert record["measurements"] == []


@pytest.mark.parametrize(
    "change",
    [
        {"checks": []},
        {"schema": True},
        {"checks": [None]},
        {
            "checks": [
                {
                    "target": "fixture",
                    "check": "fixture",
                    "phase": "unknown",
                    "system": "x86_64-linux",
                }
            ]
        },
    ],
)
def test_malformed_manifest_rejected(change: dict) -> None:
    """An invalid required-check inventory cannot silently reduce coverage."""
    with pytest.raises(ValueError, match=r"manifest|Manifest|invalid"):
        TOOL["validate_manifest"]({"schema": 1} | change)


def test_duplicate_and_optional_only_manifests_rejected() -> None:
    """Reject ambiguous inventory and a vacuous all-optional success criterion."""
    check = {
        "target": "fixture",
        "check": "fixture",
        "phase": "build",
        "system": "x86_64-linux",
    }
    with pytest.raises(ValueError, match="Duplicate"):
        TOOL["validate_manifest"]({"schema": 1, "checks": [check, check]})
    with pytest.raises(ValueError, match="at least one"):
        TOOL["validate_manifest"]({
            "schema": 1,
            "checks": [check | {"required": False}],
        })


def test_skip_and_missing_stay_distinct(repository: Path, tmp_path: Path) -> None:
    """Record an explicit omission without turning missing or skipped work into success."""
    parser = TOOL["parser"]()
    args = parser.parse_args([
        "--source",
        str(repository),
        "skip",
        "--output",
        str(tmp_path / "evidence"),
        "--target",
        "fixture",
        "--check",
        "fixture",
        "--phase",
        "build",
        "--system",
        "aarch64-darwin",
        "--reason",
        "Native hardware unavailable",
    ])
    path, skipped = TOOL["skip_check"](args)
    check = {field: skipped[field] for field in ("target", "check", "phase", "system")}
    manifest = {"schema": 1, "checks": [check, check | {"check": "other"}]}
    result = TOOL["coverage"](repository, manifest, [TOOL["read_receipt"](path)])
    assert result["status"] == "incomplete"
    assert [row["status"] for row in result["checks"]] == ["skipped", "missing"]
    assert skipped["measurements"] == []
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest))
    status_args = parser.parse_args([
        "--source",
        str(repository),
        "status",
        str(manifest_path),
    ])
    assert TOOL["dispatch"](status_args) == 1


def test_real_verification_timeout_cleans_owned_process(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Exercise the verification deadline with an actual sleeping command adapter."""
    command = tmp_path / "nix"
    command.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(30)\n")
    command.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    monkeypatch.setitem(GLOBALS, "VERIFICATION_TIMEOUT", 0.05)
    with pytest.raises(subprocess.TimeoutExpired):
        TOOL["nix_output"](tmp_path, "eval")


def test_nix_setting_changes_prevent_comparison(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Changes in Nix execution settings become visible in the environment identity."""
    original = TOOL["environment_identity"](tmp_path, [sys.executable])
    monkeypatch.setenv("NIX_REMOTE", "fixture-remote")
    assert TOOL["environment_identity"](tmp_path, [sys.executable]) != original


@pytest.mark.parametrize("timeout", ["nan", "inf", "-1"])
def test_cli_rejects_nonfinite_timeout(
    repository: Path, tmp_path: Path, timeout: str
) -> None:
    """Reject unusable deadlines before launching the command."""
    args = TOOL["parser"]().parse_args([
        "--source",
        str(repository),
        "run",
        "--output",
        str(tmp_path / "evidence"),
        "--target",
        "fixture",
        "--check",
        "fixture",
        "--phase",
        "evaluation",
        "--timeout",
        timeout,
        "--",
        sys.executable,
        "-c",
        "pass",
    ])
    with pytest.raises(ValueError, match="positive"):
        TOOL["dispatch"](args)


def test_desktop_build_requires_canonical_recipe(
    repository: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A desktop full-system record cannot bypass the repository's build recipe."""
    monkeypatch.setattr(GLOBALS["platform"], "node", lambda: "desktop")
    with pytest.raises(ValueError, match="just os-build"):
        TOOL["capture"](
            arguments(
                repository,
                tmp_path / "evidence",
                [sys.executable, "-c", "pass"],
                phase="build",
                target="desktop",
                check="full-system",
            )
        )


def test_partial_repository_source_is_rejected(repository: Path) -> None:
    """A nested flake can read parent files that a partial fingerprint would miss."""
    nested = repository / "nested"
    nested.mkdir()
    with pytest.raises(ValueError, match="repository root"):
        TOOL["source_identity"](nested)


def test_equal_timestamp_failure_cannot_hide_behind_success(repository: Path) -> None:
    """Resolve ambiguous receipt ordering conservatively when timestamps are equal."""
    passed = benchmark([1]) | {"source": TOOL["source_identity"](repository)}
    failed = passed | {"status": "failed", "reason": "Same-time fixture failure"}
    check = {field: passed[field] for field in ("target", "check", "phase", "system")}
    manifest = {"schema": 1, "checks": [check]}
    for records in ([passed, failed], [failed, passed]):
        result = TOOL["coverage"](repository, manifest, records)
        assert result["checks"][0]["status"] == "failed"
        assert result["status"] == "incomplete"


def test_comparison_rejects_missing_or_changed_effective_nix_config() -> None:
    """Environment variables alone cannot prove effective Nix settings matched."""
    baseline = benchmark([1, 2, 3])
    with pytest.raises(ValueError, match="effective Nix"):
        TOOL["compare"](
            baseline,
            baseline
            | {
                "nix_configuration": {
                    "status": "unavailable",
                    "reason": "TimeoutExpired",
                }
            },
            10,
        )
    with pytest.raises(ValueError, match="differ"):
        TOOL["compare"](
            baseline,
            baseline
            | {"nix_configuration": {"status": "captured", "sha256": "f" * 64}},
            10,
        )


def test_nix_configuration_hash_is_canonical_and_private(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Canonicalize effective settings without retaining their private values."""
    monkeypatch.setitem(
        GLOBALS,
        "nix_output",
        lambda *_args: '{"cores": 2, "setting": "private fixture"}',
    )
    first = TOOL["nix_configuration"](tmp_path)
    monkeypatch.setitem(
        GLOBALS,
        "nix_output",
        lambda *_args: '{"setting": "private fixture", "cores": 2}',
    )
    assert TOOL["nix_configuration"](tmp_path) == first
    assert first["status"] == "captured"
    assert "private fixture" not in json.dumps(first)


def test_nix_configuration_timeout_is_explicitly_unavailable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A configuration timeout cannot masquerade as matched effective settings."""

    def unavailable(*_args: object) -> str:
        raise subprocess.TimeoutExpired(["nix", "config", "show"], 120)

    monkeypatch.setitem(GLOBALS, "nix_output", unavailable)
    assert TOOL["nix_configuration"](tmp_path) == {
        "status": "unavailable",
        "reason": "TimeoutExpired",
    }


def test_effective_configuration_change_invalidates_capture(
    repository: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Preserve both effective-setting observations when settings change mid-run."""
    observations = iter([
        {"status": "captured", "sha256": "a" * 64},
        {"status": "captured", "sha256": "b" * 64},
    ])
    monkeypatch.setitem(GLOBALS, "nix_configuration", lambda _root: next(observations))
    receipt, record = TOOL["capture"](
        arguments(repository, tmp_path / "evidence", [sys.executable, "-c", "pass"])
    )
    assert record["status"] == "invalid"
    assert record["nix_configuration"] != record["nix_configuration_after"]
    assert record["measurements"][0]["exit_code"] == 0
    assert TOOL["read_receipt"](receipt) == record


def test_coverage_orders_overlapping_runs_by_completion(repository: Path) -> None:
    """A later completed failure supersedes a faster success that started later."""
    passed = benchmark([1]) | {
        "source": TOOL["source_identity"](repository),
        "date": "2026-01-01T00:01:00+00:00",
        "finished": "2026-01-01T00:02:00+00:00",
    }
    failed = passed | {
        "date": "2026-01-01T00:00:00+00:00",
        "finished": "2026-01-01T00:10:00+00:00",
        "status": "failed",
        "reason": "Longer run failed",
    }
    check = {field: passed[field] for field in ("target", "check", "phase", "system")}
    manifest = {"schema": 1, "checks": [check]}
    for records in ([passed, failed], [failed, passed]):
        result = TOOL["coverage"](repository, manifest, records)
        assert result["status"] == "incomplete"
        assert result["checks"][0]["status"] == "failed"
        assert result["checks"][0]["finished"] == failed["finished"]


@pytest.mark.parametrize("relative", [".", "child"])
def test_staging_changed_files_preserves_source_identity(
    submodule_repository: Path, relative: str
) -> None:
    """Swapping file contents cannot reorder the fingerprint by staged blob IDs."""
    target = submodule_repository / relative
    alpha, beta = target / "alpha", target / "beta"
    alpha.write_text("left")
    beta.write_text("right")
    git_fixture(target, "add", "alpha", "beta")
    git_fixture(target, "commit", "-m", "two independently tracked fixture files")
    original = TOOL["source_identity"](submodule_repository)
    alpha.write_text("right")
    beta.write_text("left")
    unstaged = TOOL["source_identity"](submodule_repository)
    git_fixture(target, "add", "alpha", "beta")
    staged = TOOL["source_identity"](submodule_repository)
    assert staged == unstaged
    assert staged["tree_sha256"] != original["tree_sha256"]


@pytest.mark.parametrize("relative", [".", "child"])
def test_staging_deleted_file_preserves_source_identity(
    submodule_repository: Path, relative: str
) -> None:
    """Staged removals and absent tracked files describe the same effective source."""
    target = submodule_repository / relative
    removed = target / "removed"
    removed.write_text("old source")
    git_fixture(target, "add", "removed")
    git_fixture(target, "commit", "-m", "tracked deletion fixture")
    original = TOOL["source_identity"](submodule_repository)
    removed.unlink()
    unstaged = TOOL["source_identity"](submodule_repository)
    git_fixture(target, "add", "-u")
    staged = TOOL["source_identity"](submodule_repository)
    assert staged == unstaged
    assert staged["tree_sha256"] != original["tree_sha256"]


@pytest.mark.parametrize("as_bytes", [False, True])
def test_candidate_failure_keeps_private_bounded_diagnostics(
    repository: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, as_bytes: bool
) -> None:
    """A native evaluation error stays inspectable without rerunning the failure."""
    diagnostic = "upstream review guard rejected the pinned revision\n" + "x" * 100000

    def fail_verification(_root: Path, *args: str) -> str:
        raise subprocess.CalledProcessError(
            1, ["nix", *args], stderr=diagnostic.encode() if as_bytes else diagnostic
        )

    monkeypatch.setitem(GLOBALS, "nix_output", fail_verification)
    receipt, record = TOOL["capture"](
        arguments(
            repository,
            tmp_path / "evidence",
            [sys.executable, "-c", "pass"],
            phase="build",
            installable="packages.fixture",
        )
    )
    assert record["status"] == "failed"
    assert record["measurements"] == []
    log = receipt.parent / record["verification_log"]
    details = json.loads(log.read_text())
    assert details["stderr"].startswith("upstream review guard")
    assert details["stderr"].endswith("[truncated]")
    assert log.stat().st_size < 70000
    assert log.stat().st_mode & 0o777 == 0o600
