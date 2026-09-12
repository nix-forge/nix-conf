"""Check that finalization probes the retained capture only once before renaming."""

from __future__ import annotations

import json
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Disposable shell fixture.
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "hosts/nixos/desktop/minidv/minidv-finalize.sh"
RUNTIME = """
pgrep() { return 1; }
ffprobe() {
    printf 'probe\\n' >>"$PROBE_CALLS"
    cat -- "$PROBE_RESULT"
}
"""


@pytest.mark.parametrize("codec", ["dvvideo", "h264"])
def test_finalize_uses_one_probe_and_preserves_invalid_capture(
    tmp_path: Path, codec: str
) -> None:
    """Probe valid and invalid captures once; rename only the DV source."""
    tape = tmp_path / "tape"
    master = tape / "master"
    master.mkdir(parents=True)
    metadata = tape / "metadata"
    metadata.mkdir()
    (metadata / "capture-info.txt").write_text("capture_state=interrupted\n")
    partial = master / "capture001.dv"
    partial.write_bytes(b"raw frames")
    probe = tmp_path / "probe.json"
    probe.write_text(
        json.dumps({
            "streams": [
                {"codec_type": "video", "codec_name": codec},
                {"codec_type": "audio", "codec_name": "pcm_s16le"},
            ]
        })
    )
    calls = tmp_path / "calls"
    bash = shutil.which("bash")
    verify = shutil.which("true")
    assert bash is not None
    assert verify is not None
    script = tmp_path / "finalize"
    script.write_text(
        SOURCE
        .read_text()
        .replace("@bash@", bash)
        .replace("@minidvRuntime@", RUNTIME)
        .replace("@minidvVerify@", verify)
    )
    script.chmod(0o700)
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Generated fixture script.
        [str(script), "--confirm-tape-ended", str(tape)],
        env={**os.environ, "PROBE_CALLS": str(calls), "PROBE_RESULT": str(probe)},
        capture_output=True,
        check=False,
        timeout=5,
    )
    assert calls.read_text() == "probe\n"
    if codec == "dvvideo":
        assert result.returncode == 0, result.stderr
        assert (master / "tape.dv").read_bytes() == b"raw frames"
        assert not partial.exists()
    else:
        assert result.returncode == 1
        assert partial.read_bytes() == b"raw frames"
        assert not (master / "tape.dv").exists()
