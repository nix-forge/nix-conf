"""Run Commons acquisition against an isolated HTTP fixture and real images."""

import json
import os
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - isolated HTTP and image fixtures
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def _fetch(  # ruff: ignore[too-many-locals] - keep the complete disposable HTTP fixture together
    geometry: str, license_name: str = "CC BY-SA 4.0", orientation: str = "TopLeft"
) -> tuple[str, str] | None:
    bash = shutil.which("bash")
    assert bash is not None
    magick = shutil.which("magick")
    assert magick is not None
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        library = root / "wallpapers"
        binaries = root / "bin"
        binaries.mkdir()
        original = root / "original.tiff"
        subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
            [
                magick,
                "-size",
                geometry,
                "xc:steelblue",
                "-orient",
                orientation,
                str(original),
            ],
            check=True,
        )
        width, height = map(int, geometry.split("x"))
        payload = root / "api.json"
        payload.write_text(
            json.dumps({
                "query": {
                    "pages": {
                        "123": {
                            "pageid": 123,
                            "ns": 6,
                            "title": "Reviewed mountain photograph",
                            "imageinfo": [
                                {
                                    "url": "https://upload.wikimedia.org/fixture.png",
                                    "width": width,
                                    "height": height,
                                    "size": original.stat().st_size,
                                    "mime": "image/png",
                                    "metadata": [
                                        {"name": "Model", "value": "Camera model"}
                                    ],
                                    "extmetadata": {
                                        "Assessments": {"value": "featured"},
                                        "Categories": {
                                            "value": "Featured pictures of mountains"
                                        },
                                        "LicenseShortName": {"value": license_name},
                                        "Artist": {"value": "Fixture photographer"},
                                    },
                                }
                            ],
                        }
                    }
                }
            })
        )
        curl = binaries / "curl"
        curl.write_text(
            "#!"
            + bash
            + '''
set -eu
out=''
api=0
for arg in "$@"; do
  case "$arg" in
*w/api.php) api=1 ;;
gcmtitle=Category:Featured*) touch "'''
            + str(root / "curated-query")
            + '''" ;;
pageids=*) exit 99 ;;
  esac
done
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--output' ]; then out="$2"; shift; fi
  shift
done
if [ "$api" -eq 1 ]; then
  cp "'''
            + str(payload)
            + '''" "$out"
else
  cp "'''
            + str(original)
            + """" "$out"
fi
"""
        )
        curl.chmod(0o700)
        replacements = {
            "bash": bash,
            "runtimePath": str(binaries) + ":" + os.environ["PATH"],
            "wallpaperDirectory": shlex.quote(str(library)),
            "stateDirectory": shlex.quote(str(root / "state")),
            "qualityJson": shlex.quote(
                json.dumps(
                    json.loads(
                        (
                            ROOT / "modules/home/desktop/wallpaper-catalog.json"
                        ).read_text()
                    )["commonsQuality"]
                )
            ),
            "categoriesJson": shlex.quote(
                json.dumps([
                    {
                        "connection": "wikimediaCommons",
                        "category": "nature",
                        "subcategory": "mountains",
                        "collection": "Featured pictures of mountains",
                    }
                ])
            ),
            "maxCandidatePages": "3",
            "maxCandidateDownloads": "3",
            "licensesJson": "'[\"CC BY-SA 4.0\"]'",
            "userAgent": "fixture",
            "targetWidth": "3840",
            "targetHeight": "2160",
            "maxFileSizeBytes": "157286400",
            "maxImages": "30",
        }
        script = (
            ROOT
            / "modules/home/desktop/scripts/wallpaper-fetch-wikimedia-commons.sh.in"
        ).read_text()
        for key, value in replacements.items():
            script = script.replace("@" + key + "@", value)
        command = root / "fetch.sh"
        command.write_text(script)
        subprocess.run(["bash", str(command)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true, start-process-with-partial-path] - isolated image fixture
        assert (root / "curated-query").exists()
        images = list(library.glob("*.jpg"))
        if not images:
            return None
        dimensions = subprocess.check_output(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
            [magick, "identify", "-format", "%wx%h", str(images[0])],
            text=True,
        )
        metadata = Path(str(images[0]) + ".json").read_text(encoding="utf-8")
        before = images[0].stat().st_mtime_ns
        subprocess.run(["bash", str(command)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true, start-process-with-partial-path] - isolated image fixture
        assert images[0].stat().st_mtime_ns == before
        return dimensions, metadata


def test_crops_photograph_and_preserves_credit() -> None:
    """A camera-ratio original becomes native 4K with its credit and licence."""
    result = _fetch("4000x2667")
    assert result is not None
    dimensions, raw_metadata = result
    metadata = json.loads(raw_metadata)
    assert dimensions == "3840x2160"
    assert metadata["metadata"]["Artist"]["value"] == "Fixture photographer"
    assert metadata["license"] == "CC BY-SA 4.0"
    assert metadata["source_page"] == "https://commons.wikimedia.org/?curid=123"


@pytest.mark.parametrize("geometry", ["4000x4000", "6000x2160", "1920x1080"])
def test_rejects_excessive_crop_and_upscaling(geometry: str) -> None:
    """Acquisition rejects unsuitable originals before creating display files."""
    assert _fetch(geometry) is None


def test_rejects_unapproved_license() -> None:
    """A curated ID alone cannot bypass the per-file licence admission rule."""
    assert _fetch("3840x2160", "All rights reserved") is None


def test_checks_geometry_after_exif_orientation() -> None:
    """A stored landscape that displays as portrait must not be upscaled."""
    assert _fetch("4000x2667", orientation="RightTop") is None
