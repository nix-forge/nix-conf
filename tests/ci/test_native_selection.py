"""Check native package selection using real Git history and Nix evaluation."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import pytest

pytestmark = [pytest.mark.nix_daemon, pytest.mark.usefixtures("isolated_git")]

SCRIPT = (
    Path(__file__).resolve().parents[2] / ".github/scripts/select-native-packages.sh"
)
DEFAULT_ENTRIES = (
    'demo = package "demo" (import ./version.nix); other = package "other" "1";'
)
QUEUE_REF = "refs/heads/gh-readonly-queue/main/pr-1-fixture"


def _command(root: Path, *args: str) -> str:
    return subprocess.check_output(args, cwd=root, text=True).strip()


def _initialize(root: Path) -> None:
    root.mkdir()
    _command(root, "git", "init", "-q", "-b", "main")
    _command(root, "git", "config", "user.name", "CI fixture")
    _command(root, "git", "config", "user.email", "ci@example.invalid")
    _command(root, "git", "config", "core.hooksPath", "/dev/null")


def _commit(root: Path) -> str:
    _command(root, "git", "add", ".")
    _command(root, "git", "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
    return _command(root, "git", "rev-parse", "HEAD")


def _flake(root: Path, entries: str = DEFAULT_ENTRIES) -> None:
    (root / "flake.nix").write_text(
        "{ inputs.self.submodules = true; outputs = { self }: let package = name: version: builtins.derivation "
        '{ name = name + "-" + version; system = "x86_64-linux"; builder = "/bin/sh"; }; '
        "in { packages.x86_64-linux = { " + entries + " }; }; }\n"
    )


class NativeSelectionFixture(unittest.TestCase):
    """Exercise selection boundaries without building the fixture derivations."""

    def setUp(self) -> None:
        """Create a committed baseline and a documentation-only working change."""
        temporary = tempfile.TemporaryDirectory(prefix="native-selection-")
        self.addCleanup(temporary.cleanup)
        self.parent = Path(temporary.name)
        self.root = self.parent / "repo"
        _initialize(self.root)
        self.policy = self.root / "pkgs/.github/ci-policy.json"
        self.policy.parent.mkdir(parents=True)
        self.policy.write_text("{}")
        for name in ("demo", "foreign"):
            recipe = self.root / "pkgs/pkgs/by-name" / name[:2] / name / "package.nix"
            recipe.parent.mkdir(parents=True)
            recipe.write_text("{ }: { }\n")
        (self.root / "version.nix").write_text('"1"\n')
        _flake(self.root)
        self.base = _commit(self.root)
        (self.root / "README.md").write_text("Documentation change\n")

    def _select(
        self,
        expected: list[str] | None,
        base: str | None = None,
        environment: dict[str, str] | None = None,
        candidates: tuple[str, ...] = (),
    ) -> None:
        if _command(self.root, "git", "status", "--porcelain"):
            _commit(self.root)
        settings = (
            os.environ
            | {
                "TARGET_SYSTEM": "x86_64-linux",
                "BASE_SHA": self.base if base is None else base,
                "GITHUB_EVENT_NAME": "pull_request",
                "GITHUB_REF": "refs/pull/1/merge",
                "GITHUB_SHA": _command(self.root, "git", "rev-parse", "HEAD"),
                "GIT_ALLOW_PROTOCOL": "file",
            }
            | (environment or {})
        )
        result = subprocess.run(
            ["bash", str(SCRIPT), *candidates],
            cwd=self.root,
            env=settings,
            text=True,
            capture_output=True,
            check=False,
            timeout=90,
        )
        if expected is None:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual(result.stdout.strip(), "")
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                json.loads(result.stdout),
                [f'.#packages.x86_64-linux."{name}"' for name in expected],
                result.stderr,
            )

    def _change_dependency(self) -> None:
        (self.root / "version.nix").write_text('"2"\n')

    def _queue_commit(self) -> None:
        self._change_dependency()
        head = _commit(self.root)
        tree = _command(self.root, "git", "rev-parse", "HEAD^{tree}")
        queue = _command(
            self.root,
            "git",
            "commit-tree",
            tree,
            "-p",
            self.base,
            "-p",
            head,
            "-m",
            "queue fixture",
        )
        _command(self.root, "git", "checkout", "-q", queue)


class NativeSelectionTests(NativeSelectionFixture):
    """Exercise native build selection and Git history fallbacks."""

    def test_documentation(self) -> None:
        """Skip every output when only prose changes."""
        self._select([])

    def test_dependency(self) -> None:
        """Select an output when an imported dependency changes its derivation."""
        self._change_dependency()
        self._select(["demo"])

    def test_new_export(self) -> None:
        """Build a new public output even when existing recipes are unchanged."""
        _flake(self.root, DEFAULT_ENTRIES + ' extra = package "extra" "1";')
        self._select(["extra"])

    def test_removed_export(self) -> None:
        """Do not request an output removed from the current package set."""
        _flake(self.root, 'demo = package "demo" "1";')
        self._select([])

    def test_broken_retired_export_does_not_rebuild_unchanged_packages(self) -> None:
        """A removed historical output cannot invalidate remaining comparisons."""
        _flake(self.root, DEFAULT_ENTRIES + ' retired = throw "retired output";')
        self.base = _commit(self.root)
        _flake(self.root)
        self._select([])
        self._change_dependency()
        self._select(["demo"])

    def test_empty_current_set(self) -> None:
        """Return an explicit empty list instead of a default build target."""
        _flake(self.root, "")
        self._select([])

    def test_no_base(self) -> None:
        """Select all current outputs without a baseline."""
        self._select(["demo", "other"], base="")

    def test_missing_base(self) -> None:
        """Select all current outputs when history lacks the requested commit."""
        self._select(["demo", "other"], base="a" * 40)

    def test_unrelated_base(self) -> None:
        """Reject a commit outside the current branch's ancestry."""
        tree = _command(self.root, "git", "rev-parse", "HEAD^{tree}")
        unrelated = _command(
            self.root, "git", "commit-tree", tree, "-m", "unrelated fixture"
        )
        self._select(["demo", "other"], base=unrelated)

    def test_invalid_base(self) -> None:
        """Fall back to all outputs if the historical flake cannot evaluate."""
        (self.root / "flake.nix").write_text("invalid nix syntax !!!")
        self.base = _commit(self.root)
        _flake(self.root)
        self._select(["demo", "other"])

    def test_invalid_current(self) -> None:
        """Fail the command when the current flake cannot evaluate."""
        (self.root / "flake.nix").write_text("invalid nix syntax !!!")
        self._select(None)

    def test_malformed_current_map(self) -> None:
        """Reject an output whose claimed derivation path is not a store path."""
        _flake(self.root, "demo = { drvPath = 3; };")
        self._select(None)

    def test_malformed_base_map(self) -> None:
        """An invalid historical derivation map must not suppress current builds."""
        _flake(self.root, "demo = { drvPath = 3; };")
        self.base = _commit(self.root)
        _flake(self.root)
        self._select(["demo", "other"])

    def test_submodule(self) -> None:
        """Compare the old and new gitlink contents rather than one working copy."""
        child = self.parent / "child"
        _initialize(child)
        (child / "version.nix").write_text('"1"\n')
        _commit(child)
        _command(
            self.root,
            "git",
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-q",
            str(child),
            "child",
        )
        _flake(
            self.root,
            'demo = package "demo" (import ./child/version.nix); other = package "other" "1";',
        )
        self.base = _commit(self.root)
        (child / "version.nix").write_text('"2"\n')
        new_child = _commit(child)
        _command(self.root / "child", "git", "fetch", "-q", "origin")
        _command(self.root / "child", "git", "checkout", "-q", new_child)
        self._select(["demo"])

    def test_merge_group(self) -> None:
        """Use the supplied merge-group base to select changed outputs."""
        self._change_dependency()
        self._select(["demo"], environment={"GITHUB_EVENT_NAME": "merge_group"})

    def test_queue_dispatch(self) -> None:
        """Recover the actual first parent for an older queue dispatcher."""
        self._queue_commit()
        self._select(
            ["demo"],
            base="",
            environment={
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF": QUEUE_REF,
            },
        )

    def test_dispatch_wrong_sha(self) -> None:
        """Do not infer a queue base when the checkout differs from the event."""
        self._queue_commit()
        self._select(
            ["demo", "other"],
            base="",
            environment={
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF": QUEUE_REF,
                "GITHUB_SHA": self.base,
            },
        )

    def test_ordinary_dispatch(self) -> None:
        """An ordinary manual dispatch without an explicit base builds all outputs."""
        self._change_dependency()
        self._select(
            ["demo", "other"],
            base="",
            environment={
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF": "refs/heads/main",
            },
        )

    def test_single_parent_queue(self) -> None:
        """GitHub squash queues use a single-parent candidate on the base."""
        self._change_dependency()
        self._select(
            ["demo"],
            base="",
            environment={
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF": QUEUE_REF,
            },
        )

    def test_parentless_queue(self) -> None:
        """A queue-shaped event without a parent must fall back to full builds."""
        _commit(self.root)
        tree = _command(self.root, "git", "rev-parse", "HEAD^{tree}")
        parentless = _command(
            self.root, "git", "commit-tree", tree, "-m", "root fixture"
        )
        _command(self.root, "git", "checkout", "-q", parentless)
        self._select(
            ["demo", "other"],
            base="",
            environment={
                "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REF": QUEUE_REF,
            },
        )


class HostedBuildPolicyTests(NativeSelectionFixture):
    """Apply the package repository policy to hosted build candidates."""

    def test_hosted_build_exclusion(self) -> None:
        """Honor the package repository's exclusions even without base history."""
        self.policy.write_text('{"demo": "Evaluation only: fixture restriction"}')
        self._change_dependency()
        self._select([], base=self.base)
        self._select(["other"], base="")
        self._select(["other"], base="a" * 40)

    def test_other_platform_exclusion(self) -> None:
        """A valid exclusion need not be exported on the current platform."""
        self.policy.write_text('{"foreign": "Evaluation only: another platform"}')
        self._select(["demo", "other"], base="")

    def test_representative_packages(self) -> None:
        """The smaller macOS build selection still honors shared exclusions."""
        self._select(["demo"], base="", candidates=("demo",))
        self.policy.write_text('{"demo": "Evaluation only: fixture restriction"}')
        self._select([], base="", candidates=("demo",))

    def test_unselected_packages_remain_lazy(self) -> None:
        """Neither current nor historical unselected derivations are forced."""
        _flake(self.root, 'demo = package "demo" "1"; other = throw "unselected";')
        self.base = _commit(self.root)
        self._select([], candidates=("demo",))
        self._select(["demo"], base="", candidates=("demo",))

    def test_new_representative_keeps_unchanged_base(self) -> None:
        """A missing historical candidate does not rebuild unchanged candidates."""
        _flake(self.root, DEFAULT_ENTRIES + ' extra = package "extra" "1";')
        self._select(["extra"], candidates=("demo", "extra"))

    def test_invalid_selected_package(self) -> None:
        """Projection retains selected derivation validation."""
        _flake(self.root, 'demo = { drvPath = 3; }; other = package "other" "1";')
        self._select(None, candidates=("demo",))

    def test_unknown_excluded_representative(self) -> None:
        """An exclusion cannot hide a stale explicit candidate name."""
        self.policy.write_text('{"foreign": "Evaluation only: another platform"}')
        self._select(None, candidates=("foreign",))

    def test_representative_name_is_literal(self) -> None:
        """Special characters in candidate names cannot become Nix expressions."""
        name = 'quote" slash\\ dollar${throw "interpolation"}'
        literal = json.dumps(name).replace("${", r"\${")
        _flake(self.root, f'{literal} = package "literal" "1";')
        self._select([], base=_commit(self.root), candidates=(name,))

    def test_unknown_representative(self) -> None:
        """Reject a stale explicit selection rather than silently losing coverage."""
        self._select(None, base="", candidates=("missing",))

    def test_invalid_policy(self) -> None:
        """Stop instead of building when the shared policy cannot be trusted."""
        for value in (
            None,
            "{",
            "[]",
            '{"demo": " "}',
            '{"demo": null}',
            '{"demoo": "Evaluation only: typo"}',
        ):
            with self.subTest(policy=value):
                if value is None:
                    self.policy.unlink()
                else:
                    self.policy.write_text(value)
                self._select(None, base="")
