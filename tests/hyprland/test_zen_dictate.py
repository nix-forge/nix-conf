"""Exercise Zen dictation's focus and cancellation boundaries without audio hardware."""

# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true] -- subprocesses execute only this test's disposable scripts.

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from notification_process import communicate_and_reap
from notification_process import run as run_command
from waits import wait_file

pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="The configured Zen dictation command is Linux-only"
)

SOURCE = (
    Path(__file__).resolve().parents[2]
    / "modules/home/browsers/zen/scripts/zen-dictate-linux.sh.in"
)
BASH = shutil.which("bash") or "bash"
DictationFixture = tuple[Path, dict[str, str], Path]


def _shell_fixture(name: str) -> str:
    """Load the Bash fixture.

    Returns:
        The fixture source with its interpreter selected.

    """
    return (
        (Path(__file__).with_name("fixtures") / name)
        .read_text(encoding="utf-8")
        .replace("@bash@", BASH)
    )


@pytest.fixture
def dictation(tmp_path: Path) -> DictationFixture:
    """Render the command with microphone, browser, and typing adapters.

    Returns:
        The command path, its mock environment, and the disposable runtime path.

    """
    script = tmp_path / "zen-dictate"
    script.write_text(
        SOURCE
        .read_text()
        .replace("@model@", "test-model")
        .replace("@language@", "fr")
        .replace("@recordingSeconds@", "7")
        .replace("@sampleCount@", "112000")
        .replace("@delivery@", "hyprland-urlbar")
    )
    tools = tmp_path / "bin"
    tools.mkdir()
    commands = {
        "hyprctl": _shell_fixture("zen-dictate-hyprctl.sh.in"),
        "pw-record": _shell_fixture("zen-dictate-pw-record.sh.in"),
        "whisper-cli": _shell_fixture("zen-dictate-whisper-cli.sh.in"),
        "wtype": _shell_fixture("zen-dictate-wtype.sh.in"),
        "zenity": _shell_fixture("zen-dictate-zenity.sh.in"),
        "zen-browser": _shell_fixture("zen-dictate-zen-browser.sh.in"),
        "notify-send": _shell_fixture("zen-dictate-notify-send.sh.in"),
    }
    for name, body in commands.items():
        path = tools / name
        path.write_text(body.replace("#!/bin/bash", f"#!{BASH}"))
        path.chmod(0o755)
    runtime = tmp_path / "run"
    runtime.mkdir()
    environment = os.environ | {
        "PATH": f"{tools}:{os.environ['PATH']}",
        "XDG_RUNTIME_DIR": str(runtime),
        "MOCK_STATE": str(tmp_path),
    }
    return script, environment, runtime


def test_non_hyprland_delivery_reviews_before_search(
    dictation: DictationFixture,
) -> None:
    """The generic Linux path uses a review dialog and no compositor tools."""
    script, environment, runtime = dictation
    script.write_text(
        script
        .read_text()
        .replace("hyprland-urlbar'", "review-dialog'")
        .replace("@zenExe@", str(runtime.parent / "bin/zen-browser"))
    )
    environment["MOCK_FOCUS_CHANGES"] = "1"
    result = run_command(
        [BASH, str(script), "toggle"],
        env=environment,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr.decode()
    assert (runtime.parent / "search").read_text().strip() == "--search What is Nix?"
    assert "What is Nix?" not in (runtime.parent / "dialog").read_text()
    assert (runtime.parent / "dialog-input").read_text().strip() == "What is Nix?"
    assert not (runtime.parent / "typed").exists()
    assert not (runtime.parent / "focus-count").exists()
    recorder_arguments = (
        (Path(environment["MOCK_STATE"]) / "pw-record-arguments")
        .read_text()
        .splitlines()
    )
    assert (
        recorder_arguments[recorder_arguments.index("--sample-count") + 1] == "112000"
    )
    transcription_arguments = (
        (Path(environment["MOCK_STATE"]) / "whisper-cli-arguments")
        .read_text()
        .splitlines()
    )
    assert (
        transcription_arguments[transcription_arguments.index("--language") + 1] == "fr"
    )
    assert not list((runtime / "zen-dictate").glob("session.*"))


def test_dismissed_review_does_not_search(dictation: DictationFixture) -> None:
    """The review dialog remains the final consent boundary."""
    script, environment, runtime = dictation
    script.write_text(
        script
        .read_text()
        .replace("hyprland-urlbar'", "review-dialog'")
        .replace("@zenExe@", str(runtime.parent / "bin/zen-browser"))
    )
    environment["MOCK_DISMISS_DIALOG"] = "1"
    result = run_command(
        [BASH, str(script), "toggle"],
        env=environment,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr.decode()
    assert not (runtime.parent / "search").exists()


def test_search_is_typed_only_into_the_original_zen_window(
    dictation: DictationFixture,
) -> None:
    """A successful query reaches only the Zen address bar and leaves no audio."""
    script, environment, runtime = dictation
    result = run_command(
        [BASH, str(script), "toggle"],
        env=environment,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr.decode()
    assert (runtime.parent / "typed").read_text().splitlines() == [
        "-M ctrl -k l -m ctrl",
        "-- What is Nix?",
    ]
    assert not list((runtime / "zen-dictate").glob("session.*"))


def test_focus_change_discards_transcription(dictation: DictationFixture) -> None:
    """Changing focus before delivery prevents typing into another window."""
    script, environment, runtime = dictation
    environment["MOCK_FOCUS_CHANGES"] = "1"
    result = run_command(
        [BASH, str(script), "toggle"],
        env=environment,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert result.returncode == 1
    assert not (runtime.parent / "typed").exists()
    assert not list((runtime / "zen-dictate").glob("session.*"))


def test_cancel_discards_audio_without_transcribing(
    dictation: DictationFixture,
) -> None:
    """Cancellation stops capture and removes audio without delivering text."""
    script, environment, runtime = dictation
    environment["MOCK_HOLD_RECORDING"] = "1"
    process = subprocess.Popen(
        [BASH, str(script), "toggle"],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        pid_file = runtime / "zen-dictate/pid"
        wait_file(pid_file)
        run_command(
            [BASH, str(script), "cancel"], env=environment, check=True, timeout=5
        )
        _, stderr = communicate_and_reap(process, timeout=5)
        assert process.returncode == 0, stderr.decode()
        assert not (runtime.parent / "typed").exists()
        assert not list((runtime / "zen-dictate").glob("session.*"))
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()


def test_wall_clock_limit_finishes_recording(dictation: DictationFixture) -> None:
    """A stalled microphone reaches the wall limit and delivers captured speech."""
    script, environment, runtime = dictation
    script.write_text(
        script.read_text().replace("--kill-after=5s 7s", "--kill-after=5s 0.1s")
    )
    environment["MOCK_HOLD_RECORDING"] = "1"
    result = run_command(
        [BASH, str(script), "toggle"],
        env=environment,
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr.decode()
    assert (runtime.parent / "typed").read_text().splitlines()[-1] == "-- What is Nix?"
    assert not list((runtime / "zen-dictate").glob("session.*"))


def test_second_press_finishes_recording_and_types_search(
    dictation: DictationFixture,
) -> None:
    """A second shortcut press ends capture and sends the recognized query."""
    script, environment, runtime = dictation
    environment["MOCK_HOLD_RECORDING"] = "1"
    process = subprocess.Popen(
        [BASH, str(script), "toggle"],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        wait_file(runtime.parent / "recording-ready")
        run_command(
            [BASH, str(script), "toggle"], env=environment, check=True, timeout=5
        )
        _, stderr = communicate_and_reap(process, timeout=5)
        assert process.returncode == 0, stderr.decode()
        assert (runtime.parent / "typed").read_text().splitlines()[
            -1
        ] == "-- What is Nix?"
        assert not list((runtime / "zen-dictate").glob("session.*"))
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
