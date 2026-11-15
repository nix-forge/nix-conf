"""Check the security boundary between Signal's main and helper entitlements."""

import importlib.util
import plistlib
from pathlib import Path
from unittest import mock

import pytest

SPEC = importlib.util.spec_from_file_location(
    "signal_signing",
    Path(__file__).parents[2] / "overlays/temporary/scripts/sign-signal-bundle.py",
)
assert SPEC is not None
assert SPEC.loader is not None
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


def test_entitlements_remain_scoped_and_preserve_upstream(tmp_path: Path) -> None:
    """Camera access belongs to the main app; helpers receive only JIT and loading."""
    bundle = tmp_path / "Signal.app"
    frameworks = bundle / "Contents/Frameworks"
    helpers = (
        "Signal Helper",
        "Signal Helper (GPU)",
        "Signal Helper (Plugin)",
        "Signal Helper (Renderer)",
    )
    for helper in helpers:
        (frameworks / f"{helper}.app").mkdir(parents=True)
    upstream = tmp_path / "build"
    upstream.mkdir()
    main = {
        "com.apple.security.cs.allow-jit": True,
        "com.apple.security.device.camera": True,
    }
    inherit = {"com.apple.security.cs.allow-jit": True}
    for name, value in (
        ("entitlements.mac.plist", main),
        ("entitlements.mac.inherit.plist", inherit),
    ):
        (upstream / name).write_bytes(
            b"<!-- Copyright upstream -->\n\n" + plistlib.dumps(value)
        )
    calls = []

    def inspect(command: list[str], *, check: bool) -> None:
        assert check
        calls.append(command)
        assert command[:4] == ["rcodesign", "sign", "--config-file", "/dev/null"]
        assert command[-1] == str(bundle)
        flags = [
            command[index + 1]
            for index, arg in enumerate(command)
            if arg == "--code-signature-flags"
        ]
        assert set(flags) == {
            "runtime",
            *(f"Contents/Frameworks/{helper}.app:runtime" for helper in helpers),
        }
        scopes = {}
        for index, arg in enumerate(command):
            if arg != "--entitlements-xml-file":
                continue
            value = command[index + 1]
            scope, filename = value.split(":", 1) if ":" in value else ("root", value)
            scopes[scope] = plistlib.loads(Path(filename).read_bytes())
        addition = {"com.apple.security.cs.disable-library-validation": True}
        assert scopes.pop("root") == main | addition
        assert set(scopes) == {
            f"Contents/Frameworks/{helper}.app" for helper in helpers
        }
        assert all(value == inherit | addition for value in scopes.values())

    with mock.patch.object(signing.subprocess, "run", side_effect=inspect):
        signing.sign(bundle, upstream)
    assert len(calls) == 1
    assert (
        upstream / "entitlements.mac.plist"
    ).read_bytes() == b"<!-- Copyright upstream -->\n\n" + plistlib.dumps(main)


def test_unreviewed_helper_layout_fails_closed(tmp_path: Path) -> None:
    """Changed Electron layouts must be reviewed before signing any executable."""
    with (
        mock.patch.object(signing.subprocess, "run") as run,
        pytest.raises(ValueError, match="helper layout changed"),
    ):
        signing.sign(tmp_path / "Signal.app", tmp_path / "build")
    run.assert_not_called()
