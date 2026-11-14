"""Reject mixed exports and stale command inputs using real disposable Git trees."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable fixture Git repositories.
import sys
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "mac_source", Path(__file__).parents[2] / "scripts/mac_source.py"
)
assert SPEC
assert SPEC.loader
source = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(source)


def git(root: Path, *args: str) -> None:
    """Run Git only against a disposable test repository."""
    executable = shutil.which("git")
    assert executable
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Explicit fixture command.
        [
            executable,
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "commit.gpgsign=false",
            "-C",
            str(root),
            *args,
        ],
        check=True,
        capture_output=True,
    )


def repository(root: Path) -> Path:
    """Create a committed fixture with configuration and producer files.

    Returns:
        The initialized repository path.

    """
    root.mkdir()
    git(root, "init", "-q")
    git(root, "config", "user.name", "Fixture")
    git(root, "config", "user.email", "fixture@example.invalid")
    (root / "producer.nix").write_text("original producer\n")
    (root / "fixture.nix").write_text("original consumer\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "fixture")
    return root


def test_working_bytes_deletions_and_explicit_untracked(tmp_path: Path) -> None:
    """Export selected working bytes, never stale index content or ignored files."""
    repo = repository(tmp_path / "repo")
    (repo / "producer.nix").write_text("dirty working producer\n")
    (repo / "fixture.nix").unlink()
    (repo / "new.py").write_text("explicit new source\n")
    (repo / "unselected.py").write_text("excluded\n")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, ["new.py"])
    manifest = source.verify(out, identity)
    assert (out / "producer.nix").read_text() == "dirty working producer\n"
    assert set(manifest["files"]) == {"producer.nix", "new.py"}
    assert not (out / ".git").exists()


@pytest.mark.parametrize("change", ["missing", "extra", "content", "mode", "link"])
def test_remote_mixed_or_modified_tree_is_rejected(tmp_path: Path, change: str) -> None:
    """Catch the actual stale-producer/new-consumer pattern and other drift."""
    repo = repository(tmp_path / "repo")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    producer = out / "producer.nix"
    if change == "missing":
        producer.unlink()
    elif change == "extra":
        (out / "unexpected.nix").write_text("not selected\n")
    elif change == "content":
        producer.write_text("stale producer\n")
    elif change == "mode":
        producer.chmod(0o755)
    else:
        producer.unlink()
        producer.symlink_to("fixture.nix")
    with pytest.raises(source.ExportError, match="Source mismatch"):
        source.verify(out, identity)


def test_manifest_is_bound_to_callers_expected_identity(tmp_path: Path) -> None:
    """A matching file set and edited manifest cannot self-certify a mixed tree."""
    repo = repository(tmp_path / "repo")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    (out / "producer.nix").write_text("different\n")
    manifest = json.loads((out / source.MANIFEST).read_text())
    manifest["files"] = source.tree_files(out)
    (out / source.MANIFEST).write_text(json.dumps(manifest))
    with pytest.raises(source.ExportError, match="expected export identity"):
        source.verify(out, identity)


def test_nested_submodule_dirty_bytes_and_missing_checkout(tmp_path: Path) -> None:
    """Keep root and nested repository changes in a single verifiable selection."""
    dependency = repository(tmp_path / "dependency")
    repo = repository(tmp_path / "repo")
    git(
        repo,
        "-c",
        "protocol.file.allow=always",
        "submodule",
        "add",
        str(dependency),
        "module",
    )
    git(repo, "commit", "-qam", "module")
    (repo / "module/producer.nix").write_text("dirty dependency\n")
    (repo / "module/untracked.nix").write_text("explicit submodule source\n")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, ["module/untracked.nix"])
    assert (out / "module/untracked.nix").read_text() == "explicit submodule source\n"
    assert (out / "module/producer.nix").read_text() == "dirty dependency\n"
    assert "module" in source.verify(out, identity)["repositories"]
    git(repo, "submodule", "deinit", "-f", "module")
    with pytest.raises(source.ExportError, match="not initialized"):
        source.working_tree(repo, [])


def test_source_mutation_during_copy_never_publishes_manifest(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Reject a concurrent writer instead of publishing a mixed snapshot."""
    repo = repository(tmp_path / "repo")
    original = source.shutil.copyfile

    def racing_copy(start: Path, end: Path) -> None:
        """Copy selected bytes, then simulate a writer changing their producer."""
        original(start, end)
        (repo / "producer.nix").write_text("concurrent change\n")

    monkeypatch.setattr(source.shutil, "copyfile", racing_copy)
    out = tmp_path / "snapshot"
    with pytest.raises(
        source.ExportError, match=r"changed during export|Source mismatch"
    ):
        source.snapshot(repo, out, [])
    assert not (out / source.MANIFEST).exists()


def test_stale_local_source_blocks_command_before_ssh(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Do not launch a test against a previous source export."""
    repo = repository(tmp_path / "repo")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    receipt = tmp_path / "receipt.json"
    receipt.write_text(
        json.dumps({"source": str(repo), "includes": [], "identity": identity})
    )
    (repo / "producer.nix").write_text("updated locally\n")
    calls = []
    monkeypatch.setattr(source, "remote", lambda *_: calls.append(True))
    with pytest.raises(source.ExportError, match="Local source changed"):
        source.run(
            argparse.Namespace(receipt=str(receipt), command=["--", "nix", "build"])
        )
    assert not calls


@pytest.mark.parametrize("name", ["../escape", "/absolute", ".git/config"])
def test_explicit_paths_cannot_escape_source(tmp_path: Path, name: str) -> None:
    """Do not export Git credentials or paths outside the source selection."""
    repo = repository(tmp_path / "repo")
    with pytest.raises(source.ExportError, match="Unsafe export path"):
        source.snapshot(repo, tmp_path / "snapshot", [name])


def test_ignored_includes_and_external_symlinks_are_rejected(tmp_path: Path) -> None:
    """Explicit selection cannot accidentally publish ignored private data."""
    repo = repository(tmp_path / "repo")
    (repo / ".gitignore").write_text("private\n")
    (repo / "private").write_text("not exported\n")
    with pytest.raises(source.ExportError, match="Ignored"):
        source.working_tree(repo, ["private"])
    (repo / "external").symlink_to("../outside")
    git(repo, "add", "external")
    with pytest.raises(source.ExportError, match="escapes"):
        source.working_tree(repo, [])


def test_internal_symlinks_and_intent_to_add_are_preserved(tmp_path: Path) -> None:
    """Git's selected new files and relative links survive Nix mode normalization."""
    repo = repository(tmp_path / "repo")
    (repo / "new.nix").write_text("new working bytes\n")
    (repo / "link").symlink_to("producer.nix")
    git(repo, "add", "-N", "new.nix", "link")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    assert (out / "new.nix").read_text() == "new working bytes\n"
    assert (out / "link").readlink() == Path("producer.nix")
    for path in out.iterdir():
        if not path.is_symlink():
            path.chmod(0o444)
    source.verify(out, identity)


@pytest.mark.parametrize("tamper_before", [True, False])
def test_verification_surrounds_actual_child_execution(
    tmp_path: Path, *, tamper_before: bool
) -> None:
    """Never start a child for stale input; never pass a source-mutating child."""
    repo = repository(tmp_path / "repo")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    marker = tmp_path / "command-ran"
    if tamper_before:
        (out / "producer.nix").write_text("stale producer\n")
    command = [
        sys.executable,
        str(Path(__file__).parent / "fixtures/source_command.py"),
        str(marker),
        str(out / "producer.nix"),
    ]
    with pytest.raises(source.ExportError, match="Source mismatch"):
        source.execute_verified(out, identity, command)
    assert marker.exists() is not tamper_before


def test_local_drift_after_command_invalidates_success_receipt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A concurrent local edit cannot leave an apparently current success receipt."""
    repo = repository(tmp_path / "repo")
    identity = source.snapshot(repo, tmp_path / "snapshot", [])
    receipt = tmp_path / "receipt.json"
    receipt.write_text(
        json.dumps({"source": str(repo), "includes": [], "identity": identity})
    )

    def remote(*_: object) -> int:
        """Simulate a successful command while the local source changes.

        Returns:
            The simulated successful command result.

        """
        (repo / "producer.nix").write_text("changed during command\n")
        return 0

    monkeypatch.setattr(source, "remote", remote)
    with pytest.raises(source.ExportError, match="Local source changed"):
        source.run(argparse.Namespace(receipt=str(receipt), command=["true"]))
    result = json.loads(
        Path(str(receipt) + ".last-run.json").read_text(encoding="utf-8")
    )
    assert result["status"] == "failed"
    assert result["exitCode"] == 1


@pytest.mark.parametrize(
    "arguments",
    [
        ["nix", "build", "path:/tmp/old-export#checks.test"],
        ["nix", "build", "--expr", 'builtins.getFlake "/old/export"'],
        ["nix", "build", "--file=../old.nix"],
        ["nix", "build", "./../old-export#test"],
        ["nix", "build", "github:example/other#default"],
        ["nix", "build", "old-export"],
        ["nix", "build", "--cores", "4", "nixpkgs"],
        ["nix", "build", "--json=true", ".#test"],
        ["env", "SETTING=value", "nix", "build", "/old/export"],
    ],
)
def test_nix_command_cannot_certify_unrelated_source(
    tmp_path: Path, arguments: list[str]
) -> None:
    """Block accidental reuse of earlier mutable exports before Nix starts."""
    with pytest.raises(source.ExportError, match=r"Nix source|Nix switch"):
        source.validate_nix_source(tmp_path, arguments)


def test_nix_snapshot_installable_and_output_path_are_supported(tmp_path: Path) -> None:
    """Build only the verified source while allowing a separate result link."""
    source.validate_nix_source(
        tmp_path,
        [
            "nix",
            "build",
            f"path:{tmp_path}#checks.test",
            "--out-link",
            str(tmp_path.parent / "result"),
        ],
    )
    source.validate_nix_source(tmp_path, ["nix", "build", ".#checks.test"])


def test_default_test_command_uses_pinned_snapshot_environment() -> None:
    """Native tests must use the exported source's test Python and dependencies."""
    command = source.default_command("test", ["-q", "tests/macos/test_mac_source.py"])
    assert command[:2] == ["nix", "develop"]
    assert ".#tests" in command
    assert command[-5:] == [
        "pytest",
        "-p",
        "no:cacheprovider",
        "-q",
        "tests/macos/test_mac_source.py",
    ]
    source.validate_nix_source(
        Path("/nix/store/source"),
        [part.replace("{source}", "/nix/store/source") for part in command],  # ruff: ignore[missing-f-string-syntax] - Reserved source token.,
    )


def test_automatic_workflow_always_exports_before_launch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The default path creates a distinct fresh receipt before every command."""
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    calls = []

    def export(args: argparse.Namespace) -> None:
        """Record the required source export before the run."""
        calls.append(("export", args.receipt))

    def run(args: argparse.Namespace) -> int:
        """Record the checked execution.

        Returns:
            The simulated native command status.

        """
        calls.append(("run", args.receipt))
        return 0

    monkeypatch.setattr(source, "export", export)
    monkeypatch.setattr(source, "run", run)
    args = argparse.Namespace(source="repo", host="macbook", kind="check", command=[])
    assert source.automatic(args) == 0
    assert source.automatic(args) == 0
    assert [kind for kind, _ in calls] == ["export", "run", "export", "run"]
    assert calls[0][1] == calls[1][1]
    assert calls[2][1] == calls[3][1]
    assert calls[0][1] != calls[2][1]


@pytest.mark.parametrize(
    "arguments",
    [
        ["path:/old/export#node"],
        ["--hostname", "other-host"],
        ["--targets", "other#node"],
        ["--", "--expr", "other"],
        ["--", "other-export#node"],
    ],
)
def test_deploy_options_cannot_replace_verified_source_or_mac(
    arguments: list[str],
) -> None:
    """User-supplied deploy options must not reroute the verified operation."""
    with pytest.raises(source.ExportError):
        source.deployment_arguments(arguments)


def test_build_preview_queues_preparation_but_not_remote_wait(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Keep dry activation, native remote build and desktop queue placement."""
    repo = repository(tmp_path / "repo")
    out = tmp_path / "snapshot"
    identity = source.snapshot(repo, out, [])
    receipt = {
        "source": str(repo),
        "includes": [],
        "identity": identity,
        "snapshot": str(out),
        "host": "macbook",
        "clientRoot": str(tmp_path / "client-result"),
    }
    calls = []
    nix = tmp_path / "nix"
    nix.write_text("#!/bin/sh\nexit 97\n", encoding="utf-8")
    nix.chmod(0o700)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])

    def capture(*args: str) -> bytes:
        """Provide immutable client and node metadata from queued preparation.

        Returns:
            Fixed Nix metadata for the test.

        """
        assert args[0] == "workstation-task"
        calls.append(args)
        if "eval" in args:
            return json.dumps({
                "hostname": "macbook",
                "profileUser": "root",
            }).encode()
        return json.dumps([{"outputs": {"out": "/nix/store/deploy-client"}}]).encode()

    def run(command: list[str], **kwargs: object) -> argparse.Namespace:
        """Capture the exact deployment command outside the workload queue.

        Returns:
            The simulated successful deploy-rs outcome.

        """
        environment = kwargs["env"]
        assert isinstance(environment, dict)
        assert environment["MAC_DEPLOY_NIX"] == str(nix.resolve())
        assert command[0] == "/nix/store/deploy-client/bin/deploy"
        assert "workstation-task" not in command
        assert "--dry-activate" in command
        assert f"path:{out}#macbook-pro-m4.system" in command
        assert "--remote-build" in command
        assert command[command.index("--ssh-user") + 1] == "root"
        assert command[command.index("--profile-user") + 1] == "root"
        assert command[-5:] == [
            "--max-jobs",
            "2",
            "--cores",
            "4",
            "--no-write-lock-file",
        ]
        calls.append(tuple(command))
        return argparse.Namespace(returncode=0)

    monkeypatch.setattr(source, "capture", capture)
    monkeypatch.setattr(source, "remote", lambda *_: 0)
    monkeypatch.setattr(source.subprocess, "run", run)
    # Freshness uses real Git; freeze only after the independently captured fixture.
    monkeypatch.setattr(source, "freshness", lambda _: None)
    assert (
        source.deploy_operation(
            receipt, "macbook-pro-m4", "build", ([], []), "workstation-task"
        )
        == 0
    )
    assert [call[0] for call in calls] == [
        "workstation-task",
        "workstation-task",
        "/nix/store/deploy-client/bin/deploy",
    ]


@pytest.mark.parametrize(
    "arguments",
    [
        ["eval", "path:/nix/store/source#deploy", "--json", "--apply", "node: node"],
        [
            "copy",
            "--to",
            "ssh-ng://root@macbook",
            "--derivation",
            "/nix/store/profile.drv",
        ],
    ],
)
def test_nested_deploy_local_nix_calls_are_queued(arguments: list[str]) -> None:
    """Deployment's own evaluation and copy need the same local workload policy."""
    assert source.client_nix_command(
        arguments,
        "/nix/store/nix/bin/nix",
        ["workstation-task"],
        "ssh-ng://root@macbook",
    ) == ["workstation-task", "/nix/store/nix/bin/nix", *arguments]


def test_native_remote_build_wait_does_not_hold_desktop_queue() -> None:
    """Only a derivation build against the verified Mac store bypasses the queue."""
    arguments = [
        "build",
        "/nix/store/profile.drv^out",
        "--eval-store",
        "auto",
        "--store",
        "ssh-ng://root@macbook",
    ]
    assert source.client_nix_command(
        arguments,
        "/nix/store/nix/bin/nix",
        ["workstation-task"],
        "ssh-ng://root@macbook",
    ) == ["/nix/store/nix/bin/nix", *arguments]
    with pytest.raises(source.ExportError, match="outside the verified Mac"):
        source.client_nix_command(arguments, "nix", [], "ssh-ng://root@other")
    with pytest.raises(source.ExportError, match="already evaluated"):
        source.client_nix_command(
            ["build", "nixpkgs#other", "--store", "ssh-ng://root@macbook"],
            "nix",
            [],
            "ssh-ng://root@macbook",
        )


def test_scoped_client_intercepts_actual_nested_nix_processes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Exercise the PATH shim and queue subprocesses without network or builds."""
    fixture = Path(__file__).parent / "fixtures/deploy_nix.py"
    for name in ("nix", "queue"):
        executable = tmp_path / name
        executable.write_text(
            "#!" + sys.executable + "\n" + fixture.read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        executable.chmod(0o700)
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    log = tmp_path / "calls.jsonl"
    monkeypatch.setenv("FIXTURE_NIX_LOG", str(log))
    receipt = {"clientRoot": str(tmp_path / "client"), "host": "macbook"}
    result = source.run_deployment_client(
        Path(__file__).parents[2],
        receipt,
        [sys.executable, str(fixture)],
        [str(tmp_path / "queue")],
    )
    assert result.returncode == 0
    calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
    assert [call["queued"] for call in calls] == [True, True, False]
    audit = Path(receipt["clientRoot"] + ".nix.jsonl")
    assert [
        json.loads(line)["queued"]
        for line in audit.read_text(encoding="utf-8").splitlines()
    ] == [
        True,
        True,
        False,
    ]


def test_store_flake_selector_is_normalized_without_changing_option_or_child_values() -> (
    None
):
    """Nix must evaluate the requested target instead of realizing its source path."""
    root = Path("/nix/store/source")
    selector = f"path:{root}#tests"
    command = [
        "env",
        "SETTING=value",
        "nix",
        "develop",
        selector,
        "--out-link",
        selector,
        "--command",
        "echo",
        selector,
    ]
    assert source.normalize_nix_source(root, command) == [
        "env",
        "SETTING=value",
        "nix",
        "develop",
        ".#tests",
        "--out-link",
        selector,
        "--command",
        "echo",
        selector,
    ]
    with pytest.raises(source.ExportError, match="snapshot root"):
        source.normalize_nix_source(root, ["nix", "build", "./subflake#test"])
