#!/usr/bin/env python3
"""Verify Zen's fullscreen HDR output through the physical DRM connector.

Requires Selenium, Pillow, geckodriver, grim, Hyprland, ffmpeg, ffprobe, and modetest. Launches an
isolated, visible profile using the supplied managed user.js. The compositor
must support HDR and return to SDR outside fullscreen. No existing tabs are used.
Use --rendering-only to check desktop rendering without requiring HDR or FFmpeg.
"""

import argparse
import json
import re
import shutil
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Runs only local test tools and the selected browser.
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Iterable
from typing import Any

# Optional integration dependencies supplied by the documented Nix command.
from PIL import Image
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.firefox.service import Service
from selenium.webdriver.support.ui import WebDriverWait

HDR_BLOB_SIZE = 32
MIN_SUSTAINED_FRAMES = 360
MAX_DROP_RATIO = 0.05
MIN_GREEN = 150


def check_rendering(
    driver: webdriver.Firefox, args: argparse.Namespace, directory: Path
) -> bool:
    """Check compositor pixels for black frames and rounded holes inside a page.

    Returns:
        Whether every sampled interior pixel remains green through scrolling
        and resizing. Browser screenshots cannot detect compositor cutouts.

    Raises:
        RuntimeError: The isolated test window is not focused on the target output.

    """
    page = directory / "rendering.html"
    page.write_text(
        "<title>Zen Wayland rendering check</title>"
        "<style>html,body{background:#00ff80;margin:0;min-height:300vh}</style>"
    )
    driver.get(page.as_uri())
    WebDriverWait(driver, 15).until(lambda d: d.title == "Zen Wayland rendering check")
    # The desktop may retain focus on the previous application at launch.
    # Select this isolated process explicitly before manipulating its window.
    browser_pid = int(driver.capabilities["moz:processID"])
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Focuses only this test's browser process.
        [args.hyprctl, "dispatch", f'hl.dsp.focus({{window="pid:{browser_pid}"}})'],
        check=True,
        capture_output=True,
    )
    time.sleep(2)

    def own_window() -> dict[str, Any]:
        window = json.loads(
            subprocess.check_output([args.hyprctl, "-j", "activewindow"])  # ruff: ignore[subprocess-without-shell-equals-true] -- Reads the selected compositor's focused window.
        )
        if "Zen Wayland rendering check" not in window.get("title", ""):
            message = "Test browser lost focus; refusing to manipulate another window"
            raise RuntimeError(message)
        return window

    own_window()
    toggle = [
        args.hyprctl,
        "dispatch",
        'hl.dsp.window.fullscreen({action="toggle",mode="maximized"})',
    ]
    subprocess.run(toggle, check=True, capture_output=True)  # ruff: ignore[subprocess-without-shell-equals-true] -- Maximizes only the verified test window.
    states = {}
    for stage in ("initial", "scroll", "resize"):
        own_window()
        if stage == "scroll":
            driver.execute_script("window.scrollTo(0,500)")
        elif stage == "resize":
            subprocess.run(toggle, check=True, capture_output=True)  # ruff: ignore[subprocess-without-shell-equals-true] -- Resizes the test window.
            time.sleep(1)
            own_window()
            subprocess.run(toggle, check=True, capture_output=True)  # ruff: ignore[subprocess-without-shell-equals-true] -- Restores the test window's maximized size.
        time.sleep(2)
        window = own_window()
        monitors = json.loads(subprocess.check_output([args.hyprctl, "-j", "monitors"]))  # ruff: ignore[subprocess-without-shell-equals-true] -- Queries only the selected local compositor.
        monitor = next(m for m in monitors if m["name"] == args.connector)
        if window["monitor"] != monitor["id"] or window["fullscreen"] != 1:
            message = "Test requires a maximized window on the selected physical output"
            raise RuntimeError(message)
        screenshot = args.output / f"rendering-{stage}.png"
        subprocess.run([args.grim, "-o", args.connector, str(screenshot)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] -- Captures displayed pixels, not the browser's internal framebuffer.
        with Image.open(screenshot) as screen:
            width, height = screen.size
            # Stay inside the page, excluding browser chrome, borders and bars.
            interior = screen.convert("RGB").crop((
                int(width * 0.25),
                int(height * 0.25),
                int(width * 0.9),
                int(height * 0.9),
            ))
            # convert("RGB") fixes the pixel shape; Pillow's return annotation
            # also includes scalar modes that cannot occur here.
            pixels = cast(
                "Iterable[tuple[int, int, int]]", interior.get_flattened_data()
            )
            bad = sum(
                not (g > MIN_GREEN and g > r * 1.5 and g > b * 1.2)
                for r, g, b in pixels
            )
        states[stage] = {"incorrect_pixels": bad}
        print(  # ruff: ignore[print] -- Reports the observed rendering verdict.
            f"{'FAIL' if bad else 'PASS'}: {stage}: {bad} incorrect interior pixels",
            flush=True,
        )
    (args.output / "rendering.json").write_text(json.dumps(states, indent=2) + "\n")
    return all(s["incorrect_pixels"] == 0 for s in states.values())


def connector_eotf(modetest: str, device: str, connector: str) -> dict[str, Any]:
    """Read the kernel's HDR metadata, not Hyprland's configured color preset.

    Returns:
        The connector EOTF and raw metadata blob.

    Raises:
        RuntimeError: The connector is absent or its metadata has an invalid size.

    """
    output = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Read-only DRM query using the selected tool.
        [modetest, "-M", "nvidia-drm", "-D", device, "-c"], text=True
    )
    match = re.search(
        rf"^\d+\s+\d+\s+connected\s+{re.escape(connector)}\b.*?"
        r"(?=^\d+\s+\d+\s+|\Z)",
        output,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        message = f"Connected output {connector} not found"
        raise RuntimeError(message)
    value = match[0].split("HDR_OUTPUT_METADATA:", 1)[1].split("value:", 1)[1]
    metadata = re.match(r"\s*((?:[0-9a-f]{32}\s*)*)", value)
    if metadata is None:
        message = "Invalid HDR metadata representation"
        raise RuntimeError(message)
    lines = metadata[1]
    blob = bytes.fromhex(lines)
    if blob and len(blob) != HDR_BLOB_SIZE:
        message = f"Unexpected HDR metadata length: {len(blob)}"
        raise RuntimeError(message)
    # drm hdr_output_metadata starts with a uint32 metadata_type, then EOTF.
    return {"eotf": blob[4] if blob else 0, "blob": blob.hex()}


def create_fixture(directory: Path) -> Path:
    """Encode a local 4K60 VP9 fixture with explicit PQ metadata.

    Returns:
        The HTML test page path.

    Raises:
        RuntimeError: FFmpeg is unavailable or the encoded HDR tags are incorrect.

    """
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        message = "ffmpeg and ffprobe must be on PATH"
        raise RuntimeError(message)
    video = directory / "hdr.webm"
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] -- Generates only a temporary local fixture.
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc2=size=3840x2160:rate=60:duration=2",
            "-vf",
            (
                "format=yuv420p10le,setparams=color_primaries=bt2020:"
                "color_trc=smpte2084:colorspace=bt2020nc"
            ),
            "-c:v",
            "libvpx-vp9",
            "-threads",
            "8",
            "-row-mt",
            "1",
            "-deadline",
            "realtime",
            "-cpu-used",
            "8",
            "-crf",
            "35",
            "-b:v",
            "0",
            "-color_primaries",
            "bt2020",
            "-color_trc",
            "smpte2084",
            "-colorspace",
            "bt2020nc",
            str(video),
        ],
        check=True,
    )
    stream = json.loads(
        subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] -- Inspects only the generated fixture.
            [
                ffprobe,
                "-v",
                "error",
                "-select_streams",
                "v:0",
                "-show_entries",
                "stream=pix_fmt,color_transfer,color_primaries",
                "-of",
                "json",
                str(video),
            ],
            text=True,
        )
    )["streams"][0]
    expected = {
        "pix_fmt": "yuv420p10le",
        "color_transfer": "smpte2084",
        "color_primaries": "bt2020",
    }
    if stream != expected:
        message = f"Incorrect HDR fixture metadata: {stream}"
        raise RuntimeError(message)
    page = directory / "index.html"
    page.write_text("""<!doctype html><meta charset="utf-8">
<title>Zen HDR output check</title>
<style>body{background:#222;color:white}video{width:640px;max-width:95vw}
video:fullscreen{width:100%;height:100%}</style>
<button onclick="document.querySelector('video').requestFullscreen()">Fullscreen HDR</button>
<video src="hdr.webm" muted loop autoplay controls></video>""")
    return page


def check(driver: webdriver.Firefox, args: argparse.Namespace, page: Path) -> bool:
    """Exercise fullscreen playback and compare kernel metadata with video progress.

    Returns:
        Whether the HDR transitions and sustained frame rate pass.

    """
    states = {}

    def snapshot(name: str) -> None:
        state = connector_eotf(args.modetest, args.drm_device, args.connector)
        state["video"] = (
            driver.execute_script("""const v=document.querySelector('video');
const q=v.getVideoPlaybackQuality();return {frames:q.totalVideoFrames,
dropped:q.droppedVideoFrames,fullscreen:!!document.fullscreenElement,
paused:v.paused,error:v.error?.message ?? null,width:v.videoWidth,height:v.videoHeight};""")
        )
        states[name] = state
        (args.output / "result.json").write_text(json.dumps(states, indent=2) + "\n")
        print(name, json.dumps(state), flush=True)  # ruff: ignore[print] -- Reports test evidence.

    driver.get(page.as_uri())
    driver.execute_script("document.querySelector('video').play()")
    wait = WebDriverWait(driver, 15)
    wait.until(
        lambda d: d.execute_script(
            "return document.querySelector('video').getVideoPlaybackQuality().totalVideoFrames > 60"
        )
    )
    snapshot("windowed")
    driver.find_element("css selector", "button").click()
    wait.until(lambda d: d.execute_script("return !!document.fullscreenElement"))
    time.sleep(3)
    snapshot("fullscreen")
    time.sleep(8)
    snapshot("sustained")
    driver.execute_script("document.exitFullscreen()")
    wait.until(lambda d: d.execute_script("return !document.fullscreenElement"))
    time.sleep(2)
    snapshot("exited")

    first, last = states["fullscreen"]["video"], states["sustained"]["video"]
    frames = last["frames"] - first["frames"]
    dropped = last["dropped"] - first["dropped"]
    passed = (
        [states[k]["eotf"] for k in states] == [0, 2, 2, 0]
        and first["fullscreen"]
        and last["fullscreen"]
        and frames >= MIN_SUSTAINED_FRAMES
        and dropped / frames < MAX_DROP_RATIO
        and all(
            s["video"]["error"] is None
            and not s["video"]["paused"]
            and (s["video"]["width"], s["video"]["height"]) == (3840, 2160)
            for s in states.values()
        )
    )
    print(  # ruff: ignore[print] -- Reports the test verdict.
        f"{'PASS' if passed else 'FAIL'}: SDR → PQ HDR → SDR; "
        f"{dropped}/{frames} frames dropped during sustained 4K60 playback"
    )
    return passed


def _wait_for_browser(browser: subprocess.Popen, port: int) -> None:
    deadline = time.monotonic() + 30
    while True:
        if browser.poll() is not None or time.monotonic() >= deadline:
            message = "Browser did not start; inspect browser.log"
            raise RuntimeError(message)
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)


def main() -> int:
    """Launch an isolated browser with the caller's managed preferences.

    Returns:
        Zero for a passing test, one for a failing test.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", default=shutil.which("zen-beta"))
    parser.add_argument("--geckodriver", default=shutil.which("geckodriver"))
    parser.add_argument("--modetest", default=shutil.which("modetest"))
    parser.add_argument("--grim", default=shutil.which("grim"))
    parser.add_argument("--hyprctl", default=shutil.which("hyprctl"))
    parser.add_argument("--rendering-only", action="store_true")
    parser.add_argument("--drm-device", default="/dev/dri/desktop-nvidia-card")
    parser.add_argument("--connector", default="DP-4")
    parser.add_argument("--user-js", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not all([args.browser, args.geckodriver, args.grim, args.hyprctl]) or (
        not args.rendering_only and not args.modetest
    ):
        parser.error("Provide browser, geckodriver, grim, and (for HDR) modetest paths")
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="zen-hdr-check-") as temporary:
        directory = Path(temporary)
        page = None if args.rendering_only else create_fixture(directory)
        profile = directory / "profile"
        profile.mkdir()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        prefs = {
            "marionette.port": port,
            "zen.welcome-screen.seen": True,
            "browser.startup.page": 0,
        }
        (profile / "user.js").write_text(
            args.user_js.read_text()
            + "\n"
            + "\n".join(
                f"user_pref({json.dumps(k)}, {json.dumps(v)});"
                for k, v in prefs.items()
            )
        )
        driver = None
        with (args.output / "browser.log").open("w") as log:
            browser = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] -- Runs the selected browser in a temporary profile.
                [
                    args.browser,
                    "-no-remote",
                    "-profile",
                    str(profile),
                    "-marionette",
                    "--remote-allow-system-access",
                ],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                _wait_for_browser(browser, port)
                driver = webdriver.Firefox(
                    options=Options(),
                    service=Service(
                        args.geckodriver,
                        service_args=[
                            "--connect-existing",
                            "--marionette-port",
                            str(port),
                        ],
                        log_output=str(args.output / "geckodriver.log"),
                    ),
                )
                if not check_rendering(driver, args, directory):
                    return 1
                if page is None:
                    return 0
                return 0 if check(driver, args, page) else 1
            finally:
                try:
                    if driver is not None:
                        driver.quit()
                finally:
                    browser.terminate()
                    try:
                        browser.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        browser.kill()
                        browser.wait()


if __name__ == "__main__":
    raise SystemExit(main())
