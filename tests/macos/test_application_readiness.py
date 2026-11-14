"""Exercise capability readiness without modifying a real privacy database."""

from __future__ import annotations

import importlib.util
import json
import plistlib
import subprocess  # ruff: ignore[suspicious-subprocess-import]
import sys
from pathlib import Path
from unittest import mock

import pytest

UNKNOWN_CAPABILITIES = 2

SPEC = importlib.util.spec_from_file_location(
    "application_readiness",
    Path(__file__).parents[2] / "modules/home/macos/application_readiness.py",
)
assert SPEC is not None
assert SPEC.loader is not None
readiness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = readiness
SPEC.loader.exec_module(readiness)


class FixtureInspector(readiness.NativeInspector):
    """Model independently observed OS/build and signed application identities."""

    def __init__(self) -> None:
        """Start with a valid signed application and no UI operations."""
        self.version = ("27.0.1", "26A100")
        self.failure: str | None = None
        self.bundle_id = "org.example.app"
        self.team = "EXAMPLETEAM"
        self.fingerprint = "original-binary"
        self.opens: list[tuple[Path, bool]] = []

    def system(self) -> tuple[str, str]:
        """Return simulated OS identity.

        Returns:
            The product and build version.

        """
        return self.version

    def inspect(self, path: Path) -> readiness.Identity:
        """Return a fixture independent of declared permission intent.

        Returns:
            The simulated installed app's identity.

        """
        assert path.name.endswith(".app")
        if self.failure:
            raise readiness.ReadinessError(self.failure)
        return readiness.Identity(
            self.bundle_id,
            "1.0",
            self.team,
            "identifier org.example.app",
            "123456",
            "certificate",
            self.fingerprint,
        )

    def open(self, path: Path, *, settings: bool) -> None:
        """Record explicit UI requests only."""
        self.opens.append((path, settings))


def manifest_file(tmp_path: Path) -> Path:
    """Write an independent personal-Mac example.

    Returns:
        The manifest file.

    """
    path = tmp_path / "manifest.json"
    path.write_text(
        json.dumps({
            "schemaVersion": 1,
            "appsDirectory": str(tmp_path / "Apps with spaces"),
            "stateDirectory": str(tmp_path / "state"),
            "apps": {
                "example": {
                    "bundle": "Example App.app",
                    "bundleId": "org.example.app",
                    "teamId": "EXAMPLETEAM",
                    "features": {
                        "lan": {
                            "service": "local-network",
                            "reason": "Connect to selected local devices",
                            "source": "https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy",
                            "instruction": "Connect from the app GUI to a chosen test service.",
                            "minimumOS": 15,
                        }
                    },
                }
            },
        }),
        encoding="utf-8",
    )
    return path


def invoke(path: Path, native: FixtureInspector, *args: str) -> int:
    """Use the command's real parser and dispatch.

    Returns:
        The public command exit status.

    """
    return readiness.main(["--manifest", str(path), *args], inspector=native)


def test_check_is_read_only_and_does_not_infer_consent(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    """Successful native identity inspection cannot establish GUI permission."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    before = path.read_bytes()
    assert invoke(path, native, "--check", "--json") == UNKNOWN_CAPABILITIES
    first = json.loads(capsys.readouterr().out)
    assert first["apps"][0]["identityStatus"] == "ready"
    assert first["apps"][0]["features"][0]["observed"] == "unknown"
    assert invoke(path, native, "--check", "--json") == UNKNOWN_CAPABILITIES
    assert json.loads(capsys.readouterr().out) == first
    assert path.read_bytes() == before
    assert not (tmp_path / "state").exists()
    assert native.opens == []


@pytest.mark.parametrize(
    "failure", ["Missing copied app", "Malformed Info.plist", "Invalid resource seal"]
)
def test_bad_native_identity_blocks_guidance_and_receipt(
    tmp_path: Path, failure: str
) -> None:
    """Signature, parse, and missing-file failures cannot be bypassed by recording."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    native.failure = failure
    assert invoke(path, native, "--guide", "example", "lan", "--open", "app") == 1
    assert (
        invoke(
            path,
            native,
            "--verify",
            "example",
            "lan",
            "--result",
            "passed",
            "--origin",
            "gui-app",
            "--evidence",
            "Actual GUI connection",
        )
        == 1
    )
    assert not (tmp_path / "state").exists()
    assert native.opens == []


@pytest.mark.parametrize(
    ("attribute", "value"), [("bundle_id", "org.example.other"), ("team", "DIFFERENT")]
)
def test_wrong_bundle_or_team_blocks_check(
    tmp_path: Path, attribute: str, value: str
) -> None:
    """A valid signature belonging to another identity is insufficient."""
    native = FixtureInspector()
    setattr(native, attribute, value)
    assert invoke(manifest_file(tmp_path), native, "--check") == 1


@pytest.mark.parametrize(
    "change",
    [
        "bundle",
        "identifier",
        "traversal",
        "unsafe-key",
        "service",
        "source",
        "version",
        "boolean-version",
    ],
)
def test_manifest_rejects_unsafe_or_impossible_inputs(
    tmp_path: Path, change: str
) -> None:
    """External manifest validation happens before native inspection or writes."""
    path = manifest_file(tmp_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    app = data["apps"]["example"]
    if change in {"bundle", "identifier"}:
        data["apps"]["duplicate"] = {
            **app,
            "bundle": "Other.app" if change == "identifier" else "Example App.app",
            "bundleId": "org.example.other" if change == "bundle" else app["bundleId"],
        }
    elif change == "traversal":
        app["bundle"] = "../Example.app"
    elif change == "unsafe-key":
        data["apps"]["../outside"] = data["apps"].pop("example")
    elif change == "service":
        app["features"]["lan"]["service"] = "silent-local-network-grant"
    elif change == "source":
        app["features"]["lan"]["source"] = "file:///private"
    else:
        app["features"]["lan"]["minimumOS"] = True if change == "boolean-version" else 0
    path.write_text(json.dumps(data), encoding="utf-8")
    assert invoke(path, FixtureInspector(), "--check") == 1
    assert not (tmp_path / "state").exists()


@pytest.mark.parametrize("mode", ["--guide", "--verify"])
def test_disabled_or_unknown_feature_cannot_be_selected(
    tmp_path: Path, mode: str
) -> None:
    """The command accepts only features present in the generated manifest."""
    assert (
        invoke(manifest_file(tmp_path), FixtureInspector(), mode, "example", "disabled")
        == 1
    )


def test_guidance_opens_ui_only_when_explicit(tmp_path: Path) -> None:
    """A text checklist is safe over SSH; opening UI is a separate flag."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    assert invoke(path, native, "--guide", "example", "lan") == 0
    assert native.opens == []
    assert invoke(path, native, "--guide", "example", "lan", "--open", "settings") == 0
    assert native.opens == [(tmp_path / "Apps with spaces/Example App.app", True)]


@pytest.mark.parametrize("change", ["binary", "os-build", "instruction", "none"])
def test_operator_evidence_is_historical_and_becomes_stale(
    tmp_path: Path, change: str, capsys: pytest.CaptureFixture[str]
) -> None:
    """Recording a feature result never fabricates current permission state."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    assert (
        invoke(
            path,
            native,
            "--verify",
            "example",
            "lan",
            "--result",
            "passed",
            "--origin",
            "gui-app",
            "--evidence",
            "Connected in the GUI to a disposable test service",
        )
        == 0
    )
    capsys.readouterr()
    if change == "binary":
        native.fingerprint = "updated-binary"
    elif change == "os-build":
        native.version = ("27.0.1", "26A101")
    elif change == "instruction":
        data = json.loads(path.read_text(encoding="utf-8"))
        data["apps"]["example"]["features"]["lan"]["instruction"] = (
            "New feature operation"
        )
        path.write_text(json.dumps(data), encoding="utf-8")
    assert invoke(path, native, "--check", "--json") == UNKNOWN_CAPABILITIES
    feature = json.loads(capsys.readouterr().out)["apps"][0]["features"][0]
    assert feature["status"] == "unknown"
    assert feature["lastVerification"]["result"] == "passed"
    assert feature["lastVerification"]["stale"] == (change != "none")
    assert (tmp_path / "state").stat().st_mode & 0o077 == 0
    assert next((tmp_path / "state").glob("*.json")).stat().st_mode & 0o077 == 0


@pytest.mark.parametrize(
    "extra", [[], ["--result", "passed"], ["--result", "passed", "--origin", "gui-app"]]
)
def test_verify_requires_origin_and_real_feature_description(
    tmp_path: Path, extra: list[str]
) -> None:
    """A permission toggle or command success alone cannot record a GUI feature."""
    assert (
        invoke(
            manifest_file(tmp_path),
            FixtureInspector(),
            "--verify",
            "example",
            "lan",
            *extra,
        )
        == 1
    )
    assert not (tmp_path / "state").exists()


def test_unsupported_os_blocks_guidance_and_labels_check(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    """A capability introduced on a newer OS cannot be reported ready."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    native.version = ("14.7", "23G1")
    assert invoke(path, native, "--check", "--json") == UNKNOWN_CAPABILITIES
    assert (
        json.loads(capsys.readouterr().out)["apps"][0]["features"][0]["status"]
        == "unsupported"
    )
    assert invoke(path, native, "--guide", "example", "lan") == 1


def test_corrupted_or_symlinked_evidence_cannot_authorize(tmp_path: Path) -> None:
    """Forged receipts remain untrusted historical data, never grants."""
    evidence = tmp_path / "receipt.json"
    evidence.write_text("{broken", encoding="utf-8")
    assert readiness.read_receipt(evidence, "key")["stale"]
    evidence.unlink()
    target = tmp_path / "target.json"
    target.write_text("{}", encoding="utf-8")
    evidence.symlink_to(target)
    assert readiness.read_receipt(evidence, "key")["stale"]


def test_interrupted_write_preserves_old_evidence_and_removes_temporary(
    tmp_path: Path,
) -> None:
    """A failed atomic replacement cannot leave half a success receipt."""
    directory = tmp_path / "private"
    directory.mkdir(mode=0o700)
    path = directory / "test.json"
    path.write_text('{"previous":true}', encoding="utf-8")
    with (
        mock.patch.object(
            Path, "replace", side_effect=OSError("simulated interruption")
        ),
        pytest.raises(OSError, match="simulated interruption"),
    ):
        readiness.write_receipt(path, {"new": True})
    assert json.loads(path.read_text(encoding="utf-8")) == {"previous": True}
    assert not list(directory.glob(".receipt-*"))


@pytest.mark.parametrize("unsafe", ["symlink", "public"])
def test_evidence_writer_rejects_unsafe_directory(tmp_path: Path, unsafe: str) -> None:
    """Evidence must stay in a private directory owned by the current user."""
    directory = tmp_path / "state"
    if unsafe == "symlink":
        target = tmp_path / "target"
        target.mkdir(mode=0o700)
        directory.symlink_to(target, target_is_directory=True)
    else:
        directory.mkdir(mode=0o755)
        directory.chmod(0o755)
    with pytest.raises(readiness.ReadinessError):
        readiness.write_receipt(directory / "evidence.json", {"result": "passed"})


@pytest.mark.parametrize(
    ("requirement_line", "expected_requirement"),
    [
        (
            "designated => identifier org.example.app and anchor apple generic",
            "identifier org.example.app and anchor apple generic",
        ),
        ('# designated => cdhash H"abcdef"', 'cdhash H"abcdef"'),
    ],
)
def test_native_inspector_handles_binary_plists_and_space_paths(
    tmp_path: Path, requirement_line: str, expected_requirement: str
) -> None:
    """Use a real binary plist and independent recorded codesign output."""
    app = tmp_path / "Space App.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents/Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleIdentifier": "org.example.app",
                "CFBundleShortVersionString": "1.2",
            },
            fmt=plistlib.FMT_BINARY,
        )
    )
    details = (
        "Identifier=org.example.app\nTeamIdentifier=EXAMPLETEAM\nCDHash=abcdef\nAuthority=Example\n"
        + requirement_line
        + "\n"
    )
    with mock.patch.object(
        readiness.NativeInspector, "run", side_effect=["", details]
    ) as run:
        identity = readiness.NativeInspector().inspect(app)
    assert identity.bundle_id == "org.example.app"
    assert identity.requirement == expected_requirement
    assert run.call_args_list[0].args[0][-1] == str(app)
    assert "--all-architectures" in run.call_args_list[0].args[0]


@pytest.mark.parametrize("kind", ["missing", "bad-plist", "symlink"])
def test_native_inspector_rejects_invalid_copied_bundles(
    tmp_path: Path, kind: str
) -> None:
    """Invalid bundle files fail before launching any native command."""
    app = tmp_path / "App.app"
    if kind == "symlink":
        target = tmp_path / "target"
        target.mkdir()
        app.symlink_to(target, target_is_directory=True)
    elif kind == "bad-plist":
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(b"broken plist")
    with (
        mock.patch.object(readiness.NativeInspector, "run") as run,
        pytest.raises((OSError, ValueError, readiness.ReadinessError)),
    ):
        readiness.NativeInspector().inspect(app)
    run.assert_not_called()


def test_concurrent_process_writers_leave_complete_private_receipt(
    tmp_path: Path,
) -> None:
    """Independent invocations serialize on one private lock without truncation."""
    path = tmp_path / "private/evidence.json"
    fixture = Path(__file__).with_name("fixtures") / "write_readiness_receipt.py"
    children = [
        subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true]
            [
                sys.executable,
                str(fixture),
                str(
                    Path(__file__).parents[2]
                    / "modules/home/macos/application_readiness.py"
                ),
                str(path),
                str(index),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        for index in range(6)
    ]
    for child in children:
        _, error = child.communicate(timeout=20)
        assert child.returncode == 0, error
    receipt = json.loads(path.read_text(encoding="utf-8"))
    assert receipt["writer"] in range(6)
    assert receipt["payload"] == "x" * 10000
    assert not list(path.parent.glob(".receipt-*"))
    assert path.stat().st_mode & 0o077 == 0


def test_dotted_identifiers_have_separate_evidence_paths(tmp_path: Path) -> None:
    """Different app/feature tuples cannot overwrite each other's receipts."""
    path = manifest_file(tmp_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    app = data["apps"].pop("example")
    data["apps"]["foo.bar"] = app
    data["apps"]["foo"] = {
        **app,
        "bundle": "Other.app",
        "bundleId": "org.example.other",
        "features": {"bar.lan": app["features"]["lan"]},
    }
    path.write_text(json.dumps(data), encoding="utf-8")
    native = FixtureInspector()
    first = native.inspect(Path("Example App.app"))
    second = readiness.Identity(
        "org.example.other",
        "1.0",
        "EXAMPLETEAM",
        "identifier org.example.other",
        "abc",
        "certificate",
        "other",
    )
    with mock.patch.object(
        native,
        "inspect",
        side_effect=lambda app_path: second if app_path.name == "Other.app" else first,
    ):
        for app_key, feature_key in [("foo.bar", "lan"), ("foo", "bar.lan")]:
            assert (
                invoke(
                    path,
                    native,
                    "--verify",
                    app_key,
                    feature_key,
                    "--result",
                    "passed",
                    "--origin",
                    "gui-app",
                    "--evidence",
                    app_key,
                )
                == 0
            )
    receipts = [
        json.loads(p.read_text(encoding="utf-8"))
        for p in (tmp_path / "state").glob("*.json")
    ]
    assert {receipt["evidence"] for receipt in receipts} == {"foo.bar", "foo"}


@pytest.mark.parametrize("bad_result", [[], {}, None, True, 1])
def test_malformed_typed_receipt_does_not_crash_check(
    tmp_path: Path, bad_result: object, capsys: pytest.CaptureFixture[str]
) -> None:
    """Valid JSON with wrong field types must not abort a read-only check."""
    path = manifest_file(tmp_path)
    native = FixtureInspector()
    assert (
        invoke(
            path,
            native,
            "--verify",
            "example",
            "lan",
            "--result",
            "passed",
            "--origin",
            "gui-app",
            "--evidence",
            "Actual GUI connection",
        )
        == 0
    )
    receipt_path = next((tmp_path / "state").glob("*.json"))
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    receipt["result"] = bad_result
    receipt_path.write_text(json.dumps(receipt), encoding="utf-8")
    capsys.readouterr()
    assert invoke(path, native, "--check", "--json") == UNKNOWN_CAPABILITIES
    feature = json.loads(capsys.readouterr().out)["apps"][0]["features"][0]
    assert feature["lastVerification"]["stale"]
    assert feature["observed"] == "unknown"
