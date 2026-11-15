"""Keep native remote waits out of the desktop compilation queue."""

import json
import runpy
import shlex
import subprocess  # ruff: ignore[suspicious-subprocess-import] - mocked process calls; no programs run.
import sys
from pathlib import Path
from unittest.mock import Mock

import pytest

MODULE = runpy.run_path(str(Path(__file__).parents[2] / "scripts/remote_realise.py"))
MAIN = MODULE["main"]
ARGUMENT_ERROR = 2
REMOTE_FAILURE = 19
DERIVATION = "/nix/store/" + "a" * 32 + "-fixture.drv"


def setup_commands(monkeypatch: pytest.MonkeyPatch, platform: str) -> Mock:
    """Replace host inspection and all external commands with controlled replies.

    Returns:
        The mock recording realization and transfer commands.

    """
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "remote-realise",
            "builder",
            DERIVATION,
            "/remote/results/native",
            "--workload-command",
            "workstation-task",
            "--protected-system",
            "workstation",
        ],
    )
    original_read = Path.read_text
    monkeypatch.setattr(
        Path,
        "read_text",
        lambda path, **kwargs: (
            "0::/session.slice"
            if str(path) == "/proc/self/cgroup"
            else original_read(path, **kwargs)
        ),
    )
    reply = Mock(
        side_effect=[
            "aarch64-darwin",
            json.dumps({DERIVATION: {"system": platform}}),
            "/nix/store/native-output\n",
        ]
    )
    monkeypatch.setattr(subprocess, "check_output", reply)
    run = Mock(return_value=subprocess.CompletedProcess([], 0))
    monkeypatch.setattr(subprocess, "run", run)
    return run


def test_copy_is_queued_but_remote_build_is_not(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Both preparation steps are bounded; remote realization owns its own work."""
    run = setup_commands(monkeypatch, "aarch64-darwin")
    assert MAIN() == 0
    assert capsys.readouterr().out == "/nix/store/native-output\n"
    commands = [entry.args[0] for entry in run.call_args_list]
    assert commands[0][:4] == ["workstation-task", "nix", "copy", "--derivation"]
    remote = shlex.split(commands[-1][-1])
    assert commands[-1][0] == "ssh"
    assert remote[:3] == ["nix-store", "--realise", DERIVATION]
    assert not remote[remote.index("--builders") + 1]
    assert remote[remote.index("--cores") + 1] == "8"


@pytest.mark.parametrize("platform", ["aarch64-linux", "x86_64-linux", "x86_64-darwin"])
def test_linux_cannot_build_on_mac(
    monkeypatch: pytest.MonkeyPatch, platform: str
) -> None:
    """A foreign platform is rejected before copying or building anything."""
    run = setup_commands(monkeypatch, platform)
    with pytest.raises(SystemExit) as error:
        MAIN()
    assert error.value.code == ARGUMENT_ERROR
    run.assert_not_called()


def test_nested_workload_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    """An outer task lock cannot silently defeat the remote-wait split."""
    run = setup_commands(monkeypatch, "aarch64-darwin")
    query = Mock()
    monkeypatch.setattr(subprocess, "check_output", query)
    monkeypatch.setattr(
        Path, "read_text", lambda *_args, **_kwargs: "0::/background-workload.slice/job"
    )
    with pytest.raises(SystemExit) as error:
        MAIN()
    assert error.value.code == ARGUMENT_ERROR
    run.assert_not_called()
    query.assert_not_called()


def test_preparation_runner_without_linux_cgroups(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A preparation runner also works on hosts without procfs."""
    run = setup_commands(monkeypatch, "aarch64-darwin")

    def absent_cgroup(*_args: object, **_kwargs: object) -> str:
        raise FileNotFoundError

    monkeypatch.setattr(Path, "read_text", absent_cgroup)
    assert MAIN() == 0
    assert run.call_args_list[0].args[0][0] == "workstation-task"


def test_remote_failure_propagates(monkeypatch: pytest.MonkeyPatch) -> None:
    """A failed remote build cannot be recorded as a successful local job."""
    run = setup_commands(monkeypatch, "aarch64-darwin")
    run.side_effect = [
        subprocess.CompletedProcess([], 0),
        subprocess.CompletedProcess([], 0),
        subprocess.CompletedProcess([], REMOTE_FAILURE),
    ]
    assert MAIN() == REMOTE_FAILURE


def test_copy_failure_does_not_start_remote_build(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A failed source transfer prevents realization of an incomplete closure."""
    run = setup_commands(monkeypatch, "aarch64-darwin")
    run.side_effect = subprocess.CalledProcessError(1, "nix copy")
    with pytest.raises(subprocess.CalledProcessError):
        MAIN()
    assert run.call_count == 1


def test_desktop_system_closure_uses_its_host_recipe(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The generic package command cannot reroute the desktop system closure."""
    run = setup_commands(monkeypatch, "aarch64-darwin")
    monkeypatch.setattr(
        subprocess,
        "check_output",
        Mock(
            side_effect=[
                "x86_64-linux",
                json.dumps({
                    DERIVATION: {
                        "system": "x86_64-linux",
                        "name": "nixos-system-workstation-test",
                    }
                }),
            ]
        ),
    )
    with pytest.raises(SystemExit) as error:
        MAIN()
    assert error.value.code == ARGUMENT_ERROR
    run.assert_not_called()


def test_root_names_cannot_be_reported_as_store_outputs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Receipt generation rejects a remote root pathname instead of an output."""
    setup_commands(monkeypatch, "aarch64-darwin")
    monkeypatch.setattr(
        subprocess,
        "check_output",
        Mock(
            side_effect=[
                "aarch64-darwin",
                json.dumps({DERIVATION: {"system": "aarch64-darwin"}}),
                "/remote/results/native\n",
            ]
        ),
    )
    with pytest.raises(SystemExit) as error:
        MAIN()
    assert error.value.code == ARGUMENT_ERROR


@pytest.mark.parametrize("version", [2, 4])
def test_modern_metadata_envelope(
    monkeypatch: pytest.MonkeyPatch, version: int
) -> None:
    """Native placement accepts the installed Nix format and supported older format."""
    setup_commands(monkeypatch, "aarch64-darwin")
    monkeypatch.setattr(
        subprocess,
        "check_output",
        Mock(
            side_effect=[
                "aarch64-darwin",
                json.dumps({
                    "version": version,
                    "derivations": {
                        Path(DERIVATION).name: {"system": "aarch64-darwin"}
                    },
                }),
                "/nix/store/native-output\n",
            ]
        ),
    )
    assert MAIN() == 0


@pytest.mark.parametrize(
    "document",
    [
        {"version": 99, "derivations": {}},
        {"version": {}, "derivations": {}},
        {"version": 4.0, "derivations": {}},
        {"version": 4, "derivations": {"wrong.drv": {"system": "aarch64-darwin"}}},
        {DERIVATION: {"system": "aarch64-darwin"}, "another.drv": {}},
    ],
)
def test_unsupported_or_wrong_metadata_is_rejected(document: object) -> None:
    """Unknown formats and mismatched derivations never bypass platform checks."""
    with pytest.raises(MODULE["DerivationMetadataError"], match=r"(?i)derivation"):
        MODULE["derivation_record"](document, Path(DERIVATION))


def test_legacy_environment_name_is_retained() -> None:
    """Desktop closure checks also see names exposed only by older Nix metadata."""
    record = MODULE["derivation_record"](
        {
            DERIVATION: {
                "system": "x86_64-linux",
                "env": {"name": "nixos-system-workstation-test"},
            }
        },
        Path(DERIVATION),
    )
    assert record["name"] == "nixos-system-workstation-test"
