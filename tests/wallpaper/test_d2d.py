"""Exercise the ESA astronomy downloader through its CLI and real image decoder."""

import json
import os
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - isolated CLI fixtures
import sys
from dataclasses import dataclass
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/home/desktop/scripts/wallpaper-fetch-d2d.py"
HOSTS = {"esaHubble": "esahubble.org", "esaWebb": "esawebb.org"}
CURL = """
import json, shutil, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
url = sys.argv[-1]
with (root / "requests").open("a") as log:
    log.write(url + "\\n")
responses = json.loads((root / "http.json").read_text())
if url not in responses or responses[url] == "FAIL":
    sys.exit(22)
out = Path(sys.argv[sys.argv.index("--output") + 1])
response = responses[url]
if response == "IMAGE":
    shutil.copyfile(root / "original.jpg", out)
elif isinstance(response, dict):
    out.write_text(json.dumps(response))
else:
    out.write_text(response)
"""
DETAIL = """<nav><a href="/images/archive/category/nebulae/">Nebulae</a></nav>
<table aria-describedby="About the Object"><tr><th scope="row">Category:</th>
<td><a href="/images/archive/category/galaxies/">Galaxies</a></td></tr></table>"""


def _item(identifier: str, connection: str = "esaHubble") -> dict:
    host = HOSTS[connection]
    return {
        "ID": identifier,
        "Title": "Spiral galaxy",
        "Description": "[Image Description: A spiral galaxy with blue stars.]",
        "Creator": "ESA",
        "Credit": "ESA/Hubble & NASA, Example team",
        "Rights": "Creative Commons Attribution 4.0 International License",
        "Priority": 80,
        "ReferenceURL": f"https://{host}/images/{identifier}/",
        "Subject": {},
        "Assets": [
            {
                "MediaType": "Image",
                "ObservationData": {
                    "Facility": ["Hubble Space Telescope"],
                    "Instrument": ["WFC3"],
                },
                "Resources": [
                    {
                        "ResourceType": "Large",
                        "MediaType": "Image",
                        "ProjectionType": "Observation",
                        "URL": f"https://cdn.{host}/archives/images/large/{identifier}.jpg",
                        "Dimensions": [384, 216],
                        "FileSize": 20000,
                    }
                ],
            }
        ],
    }


@dataclass
class Fixture:
    """An isolated provider, cache and state directory."""

    root: Path
    connection: str

    def response(self, url: str, response: dict | str) -> None:
        """Set a response at the HTTP boundary."""
        path = self.root / "http.json"
        data = json.loads(path.read_text())
        data[url] = response
        path.write_text(json.dumps(data))

    def page(self, *items: dict, number: int = 1, next_page: int | None = None) -> None:
        """Set one provider page and independent image/detail responses."""
        base = f"https://{HOSTS[self.connection]}/images/d2d/"
        self.response(
            base + (f"?page={number}" if number > 1 else ""),
            {
                "Count": len(items),
                "Next": base + f"?page={next_page}" if next_page else None,
                "Collections": list(items),
            },
        )
        for item in items:
            self.response(item["ReferenceURL"], DETAIL)
            self.response(item["Assets"][0]["Resources"][0]["URL"], "IMAGE")

    def run(self, *extra: str) -> subprocess.CompletedProcess[str]:
        """Return the real CLI result for this isolated collection.

        Returns:
            Exit status and captured output.

        """
        env = os.environ | {"PATH": str(self.root / "bin") + ":" + os.environ["PATH"]}
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated CLI
            [
                sys.executable,
                str(SCRIPT),
                "--connection",
                self.connection,
                "--plan",
                str(self.root / "plan.json"),
                "--directory",
                str(self.root / "images"),
                "--state",
                str(self.root / "state"),
                "--width",
                "384",
                "--height",
                "216",
                *extra,
            ],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )

    def images(self) -> list[Path]:
        """Return published image files.

        Returns:
            Current display JPEGs.

        """
        return list((self.root / "images").glob("*.jpg"))

    def requests(self) -> list[str]:
        """Return observed HTTP requests.

        Returns:
            Requested URLs in execution order.

        """
        path = self.root / "requests"
        return path.read_text().splitlines() if path.exists() else []


@pytest.fixture(params=list(HOSTS))
def fixture(tmp_path: Path, request: pytest.FixtureRequest) -> Fixture:
    """Return a provider fixture with real small JPEGs.

    Returns:
        A CLI fixture for either ESA connection.

    """
    magick = shutil.which("magick")
    assert magick is not None
    for directory in ["bin", "images", "state"]:
        (tmp_path / directory).mkdir()
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
        [
            magick,
            "-size",
            "384x216",
            "gradient:steelblue-navy",
            str(tmp_path / "original.jpg"),
        ],
        check=True,
    )
    curl = tmp_path / "bin/curl"
    curl.write_text("#!" + sys.executable + "\n" + CURL)
    curl.chmod(0o700)
    (tmp_path / "http.json").write_text("{}")
    (tmp_path / "plan.json").write_text(
        json.dumps([
            {
                "connection": request.param,
                "category": "space",
                "subcategory": "galaxies",
            }
        ])
    )
    return Fixture(tmp_path, request.param)


def test_acquires_classified_image_with_credit(fixture: Fixture) -> None:
    """Both providers yield native-size classified JPEGs with original credit."""
    fixture.page(_item("first", fixture.connection))
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    assert len(fixture.images()) == 1
    metadata = json.loads(
        Path(str(fixture.images()[0]) + ".json").read_text(encoding="utf-8")
    )
    assert metadata["wallpaper_categories"] == ["space/galaxies"]
    assert metadata["connection"] == fixture.connection
    assert metadata["credit"] == "ESA/Hubble & NASA, Example team"
    assert (metadata["width"], metadata["height"]) == (384, 216)
    assert metadata["license"] == "CC BY 4.0"
    assert fixture.run().returncode == 0
    assert len([url for url in fixture.requests() if "/large/" in url]) == 1


def test_continuation_and_new_arrivals(fixture: Fixture) -> None:
    """Separate processes traverse older pages, then discover fresh first-page additions."""
    fixture.page(_item("first", fixture.connection), next_page=2)
    fixture.page(_item("second", fixture.connection), number=2)
    assert fixture.run().returncode == 0
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    assert len(fixture.images()) == 2  # ruff: ignore[magic-value-comparison] - two independent acquisitions
    fixture.page(_item("third", fixture.connection), _item("first", fixture.connection))
    assert fixture.run().returncode == 0
    assert len(fixture.images()) == 3  # ruff: ignore[magic-value-comparison] - one addition per run
    feeds = [url for url in fixture.requests() if "/d2d/" in url]
    assert feeds == [
        f"https://{HOSTS[fixture.connection]}/images/d2d/",
        f"https://{HOSTS[fixture.connection]}/images/d2d/?page=2",
        f"https://{HOSTS[fixture.connection]}/images/d2d/",
    ]


def test_disabled_plan_makes_no_requests(fixture: Fixture) -> None:
    """Removing every enabled route disables acquisition before touching the network."""
    (fixture.root / "plan.json").write_text("[]")
    assert fixture.run().returncode == 0
    assert fixture.requests() == []


@pytest.mark.parametrize(
    "rejection",
    ["art", "priority", "license", "instrument", "dimensions", "visible-panels"],
)
def test_ineligible_metadata_never_downloads(fixture: Fixture, rejection: str) -> None:
    """A first-party feed alone cannot admit artwork, panels or poor source images."""
    item = _item("unsuitable", fixture.connection)
    if rejection == "art":
        item["Title"] = "A galaxy (artist's impression)"
    elif rejection == "priority":
        item["Priority"] = 70
    elif rejection == "license":
        item["Rights"] = "All rights reserved"
    elif rejection == "instrument":
        item["Assets"][0]["ObservationData"] = {}
    elif rejection == "dimensions":
        item["Assets"][0]["Resources"][0]["Dimensions"] = [384, 384]
    else:
        item["Description"] = (
            "[Image Description: Two panels compare a galaxy with a diagram.]"
        )
    fixture.page(item)
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    assert fixture.images() == []
    assert fixture.requests() == [f"https://{HOSTS[fixture.connection]}/images/d2d/"]


def test_navigation_categories_cannot_admit_wrong_subject(fixture: Fixture) -> None:
    """Only the image's category row can enable a wallpaper route."""
    fixture.page(_item("first", fixture.connection))
    (fixture.root / "plan.json").write_text(
        json.dumps([
            {
                "connection": fixture.connection,
                "category": "space",
                "subcategory": "nebulae",
            }
        ])
    )
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    assert fixture.images() == []
    assert not any("/large/" in url for url in fixture.requests())


def test_rechecks_decoded_geometry(fixture: Fixture) -> None:
    """An API claiming landscape dimensions cannot admit a decoded portrait."""
    magick = shutil.which("magick")
    assert magick is not None
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
        [magick, "-size", "216x384", "xc:navy", str(fixture.root / "original.jpg")],
        check=True,
    )
    fixture.page(_item("first", fixture.connection))
    assert fixture.run().returncode == 0
    assert fixture.images() == []


def test_failed_state_publication_rolls_back_image(fixture: Fixture) -> None:
    """State publication failure reports an error and leaves no admitted image."""
    prefix = "esa-hubble-" if fixture.connection == "esaHubble" else "esa-webb-"
    (fixture.root / "state" / (prefix + "discovery.pending")).mkdir()
    fixture.page(_item("first", fixture.connection))
    result = fixture.run()
    assert result.returncode != 0
    assert fixture.images() == []
    assert list((fixture.root / "images").glob("*.json")) == []


def test_untrusted_continuation_is_not_requested(fixture: Fixture) -> None:
    """Pagination cannot redirect the downloader to a different host."""
    base = f"https://{HOSTS[fixture.connection]}/images/d2d/"
    fixture.response(
        base, {"Collections": [], "Next": "https://untrusted.example/images/d2d/"}
    )
    result = fixture.run()
    assert result.returncode != 0
    assert fixture.requests() == [base]
    assert fixture.images() == []


def test_page_budget_and_transport_failure_preserve_progress(fixture: Fixture) -> None:
    """A budget resumes later; an HTTP failure retains that next-page cursor."""
    rejected = _item("bad", fixture.connection)
    rejected["Rights"] = "All rights reserved"
    fixture.page(rejected, next_page=2)
    fixture.page(_item("good", fixture.connection), number=2)
    assert fixture.run("--max-pages", "1").returncode == 0
    assert fixture.images() == []
    state_path = next((fixture.root / "state").glob("*discovery.json"))
    before = state_path.read_bytes()
    next_url = f"https://{HOSTS[fixture.connection]}/images/d2d/?page=2"
    fixture.response(next_url, "FAIL")
    assert fixture.run().returncode != 0
    assert state_path.read_bytes() == before
    assert fixture.images() == []
    fixture.page(_item("good", fixture.connection), number=2)
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    assert len(fixture.images()) == 1


def test_eviction_preserves_current_and_seen_history(fixture: Fixture) -> None:
    """The displayed image survives pruning and evicted IDs stay downloaded."""
    for identifier in ["first", "second"]:
        fixture.page(_item(identifier, fixture.connection))
        assert fixture.run().returncode == 0
    current = next(image for image in fixture.images() if "-first-" in image.name)
    os.utime(current, (1, 1))
    (fixture.root / "state/current").write_text(str(current))
    fixture.page(_item("third", fixture.connection))
    assert fixture.run("--max-images", "2").returncode == 0
    assert current in fixture.images()
    assert not any("-second-" in image.name for image in fixture.images())
    fixture.page(
        _item("second", fixture.connection), _item("fourth", fixture.connection)
    )
    result = fixture.run("--max-images", "2")
    assert result.returncode == 0, result.stderr
    assert current in fixture.images()
    assert any("-fourth-" in image.name for image in fixture.images())
    assert len(fixture.images()) == 2  # ruff: ignore[magic-value-comparison] - configured cache limit
    second_downloads = [url for url in fixture.requests() if "/large/second.jpg" in url]
    assert len(second_downloads) == 1


def test_keeps_all_subject_assignments_for_future_settings(fixture: Fixture) -> None:
    """A downloaded image retains disabled classifications for later cache selection."""
    item = _item("both", fixture.connection)
    fixture.page(item)
    fixture.response(
        item["ReferenceURL"],
        DETAIL.replace(
            "</td>", '<a href="/images/archive/category/nebulae/">Nebulae</a></td>'
        ),
    )
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    metadata = json.loads(
        Path(str(fixture.images()[0]) + ".json").read_text(encoding="utf-8")
    )
    assert metadata["wallpaper_categories"] == ["space/galaxies", "space/nebulae"]


def test_corrupt_media_does_not_block_later_pages(fixture: Fixture) -> None:
    """HTTP success with invalid image bytes is a content rejection, not a stuck cursor."""
    bad = _item("broken", fixture.connection)
    good = _item("later", fixture.connection)
    fixture.page(bad, next_page=2)
    fixture.page(good, number=2)
    fixture.response(bad["Assets"][0]["Resources"][0]["URL"], "not an image")
    result = fixture.run("--max-pages", "2")
    assert result.returncode == 0, result.stderr
    assert len(fixture.images()) == 1
    assert "later" in fixture.images()[0].name


@pytest.mark.parametrize("bad", [None, "not an object", {"Priority": "unknown"}])
def test_malformed_item_does_not_block_later_pages(
    fixture: Fixture, bad: object
) -> None:
    """One malformed provider record cannot starve a valid later page."""
    base = f"https://{HOSTS[fixture.connection]}/images/d2d/"
    malformed = _item("bad", fixture.connection) | bad if isinstance(bad, dict) else bad
    fixture.response(base, {"Collections": [malformed], "Next": base + "?page=2"})
    fixture.page(_item("later", fixture.connection), number=2)
    result = fixture.run("--max-pages", "2")
    assert result.returncode == 0, result.stderr
    assert len(fixture.images()) == 1
