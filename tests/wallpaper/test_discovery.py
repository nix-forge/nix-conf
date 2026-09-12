"""Exercise ongoing Commons discovery through the rendered downloader command."""

import json
import os
import shlex
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import] - isolated CLI and image fixtures
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict

import pytest

ROOT = Path(__file__).resolve().parents[2]
CATEGORY = "Featured pictures of mountains"
COAST_CATEGORY = "Featured pictures of coasts"

# Mock only HTTP. Unknown requests fail, and image decoding uses ImageMagick.
CURL_FIXTURE = """
import json
import shutil
import sys
from pathlib import Path
from typing import TypedDict

root = Path(__file__).resolve().parents[1]
args = sys.argv[1:]
config = json.loads((root / "http.json").read_text())
output = Path(args[args.index("--output") + 1])
query = {}
for index, arg in enumerate(args):
    if arg == "--data-urlencode":
        key, value = args[index + 1].split("=", 1)
        query[key] = value
is_api = "https://commons.wikimedia.org/w/api.php" in args
with (root / "requests.jsonl").open("a") as log:
    log.write(json.dumps({"api": is_api, "query": query, "args": args}) + "\\n")
if is_api:
    if query.get("generator") != "categorymembers" or "pageids" in query:
        sys.exit(99)
    key = query.get("gcmtitle", "") + "|" + query.get("gcmcontinue", "")
    response = config["routes"].get(key)
    if response is None:
        sys.exit(98)
    if response == "HTTP failure":
        sys.exit(22)
    output.write_text(json.dumps(response))
else:
    urls = [arg for arg in args if arg.startswith("https://upload.wikimedia.org/")]
    if len(urls) != 1 or urls[0] not in config["media"]:
        sys.exit(97)
    shutil.copyfile(config["media"][urls[0]], output)
"""


def _candidate(
    identifier: int,
    *,
    category: str = CATEGORY,
    title: str = "File:Mountain lake photograph.jpg",
    featured: bool = True,
    camera: bool = True,
) -> dict[str, object]:
    return {
        "ns": 6,
        "pageid": identifier,
        "title": title,
        "imageinfo": [
            {
                "url": f"https://upload.wikimedia.org/fixture-{identifier}.jpg",
                "width": 384,
                "height": 216,
                "size": 20000,
                "mime": "image/jpeg",
                "metadata": [{"name": "Model", "value": "Example camera"}]
                if camera
                else [],
                "extmetadata": {
                    "LicenseShortName": {"value": "CC BY-SA 4.0"},
                    "Artist": {"value": "Fixture photographer"},
                    "Assessments": {"value": "featured" if featured else ""},
                    "Categories": {"value": category},
                },
            }
        ],
    }


def _routes(*collections: str) -> str:
    return shlex.quote(
        json.dumps([
            {
                "connection": "wikimediaCommons",
                "category": "nature",
                "subcategory": collection.rsplit(" ", 1)[-1],
                "collection": collection,
                "excludeCollections": [
                    "Featured pictures of boats",
                    "Featured pictures of buildings",
                    "Featured pictures of cityscapes",
                ],
            }
            for collection in collections
        ])
    )


def _page(
    *candidates: dict[str, object], continuation: dict[str, str] | None = None
) -> dict[str, object]:
    page: dict[str, object] = {
        "batchcomplete": "",
        "query": {
            "pages": {str(candidate["pageid"]): candidate for candidate in candidates}
        },
    }
    if continuation is not None:
        page["continue"] = continuation
    return page


class Request(TypedDict):
    """One observed HTTP request."""

    api: bool
    query: dict[str, str]
    args: list[str]


@dataclass
class Discovery:
    """An isolated cache and HTTP boundary shared by separate CLI processes."""

    root: Path
    bash: str
    magick: str

    def route(
        self,
        response: dict[str, object] | str,
        *,
        category: str = CATEGORY,
        cursor: str = "",
    ) -> None:
        """Set one API response without changing the downloader's saved state."""
        config = json.loads((self.root / "http.json").read_text())
        config["routes"][f"Category:{category}|{cursor}"] = response
        (self.root / "http.json").write_text(json.dumps(config))

    def run(self, **options: str) -> subprocess.CompletedProcess[str]:
        """Return the result of invoking a freshly rendered production command.

        Returns:
            Exit status and captured output.

        """
        replacements = {
            "bash": self.bash,
            "runtimePath": str(self.root / "bin") + ":" + os.environ["PATH"],
            "wallpaperDirectory": shlex.quote(str(self.root / "wallpapers")),
            "stateDirectory": shlex.quote(str(self.root / "state")),
            "qualityJson": shlex.quote(
                json.dumps(
                    json.loads(
                        (
                            ROOT / "modules/home/desktop/wallpaper-catalog.json"
                        ).read_text()
                    )["commonsQuality"]
                )
            ),
            "categoriesJson": _routes(CATEGORY),
            "licensesJson": shlex.quote(json.dumps(["CC BY-SA 4.0"])),
            "userAgent": "fixture",
            "targetWidth": "384",
            "targetHeight": "216",
            "maxFileSizeBytes": "157286400",
            "maxImages": "30",
            "maxCandidatePages": "3",
            "maxCandidateDownloads": "3",
        }
        replacements.update(options)
        script = (
            ROOT
            / "modules/home/desktop/scripts/wallpaper-fetch-wikimedia-commons.sh.in"
        ).read_text()
        for key, value in replacements.items():
            script = script.replace("@" + key + "@", value)
        command = self.root / "fetch.sh"
        command.write_text(script)
        return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated CLI
            [self.bash, str(command)], capture_output=True, text=True, check=False
        )

    def requests(self, *, api: bool) -> list[Request]:
        """Return calls observed at the HTTP boundary.

        Returns:
            Recorded requests matching the requested type.

        """
        return [
            request
            for line in (self.root / "requests.jsonl").read_text().splitlines()
            if (request := json.loads(line))["api"] is api
        ]

    def state(self) -> dict:
        """Return the command's persisted discovery progress.

        Returns:
            Parsed state saved by the downloader.

        """
        return json.loads((self.root / "state/commons-discovery.json").read_text())

    def images(self) -> set[str]:
        """Return downloaded identifiers from actual cache filenames.

        Returns:
            Identifiers of the current display files.

        """
        return {
            path.name.split("-")[2] for path in (self.root / "wallpapers").glob("*.jpg")
        }

    def cache(self, identifier: int) -> Path:
        """Return an existing wallpaper seeded without invoking acquisition.

        Returns:
            Path to the seeded image.

        """
        path = self.root / f"wallpapers/wikimedia-commons-{identifier}-384x216-old.jpg"
        shutil.copyfile(self.root / "original.jpg", path)
        Path(str(path) + ".json").write_text(
            json.dumps({"source_id": str(identifier)}), encoding="utf-8"
        )
        return path


@pytest.fixture
def discovery(tmp_path: Path) -> Discovery:
    """Return real small images and an HTTP responder that records requests.

    Returns:
        Isolated command fixture with persistent cache and state.

    """
    bash = shutil.which("bash")
    magick = shutil.which("magick")
    assert bash is not None
    assert magick is not None
    for name in ("bin", "wallpapers", "state"):
        (tmp_path / name).mkdir()
    original = tmp_path / "original.jpg"
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
        [magick, "-size", "384x216", "gradient:steelblue-navy", str(original)],
        check=True,
    )
    curl = tmp_path / "bin/curl"
    curl.write_text("#!" + sys.executable + "\n" + CURL_FIXTURE)
    curl.chmod(0o700)
    (tmp_path / "http.json").write_text(
        json.dumps({
            "routes": {},
            "media": {
                f"https://upload.wikimedia.org/fixture-{identifier}.jpg": str(original)
                for identifier in range(100, 110)
            },
        })
    )
    return Discovery(tmp_path, bash, magick)


def test_scans_past_rejected_and_cached_first_page(discovery: Discovery) -> None:
    """A cache hit and an unsuitable picture cannot hide later new scenery."""
    discovery.cache(100)
    discovery.route(
        _page(
            _candidate(100),
            _candidate(101, title="File:Historical map of the mountain lake.jpg"),
            continuation={"continue": "gcmcontinue||", "gcmcontinue": "older-page"},
        )
    )
    discovery.route(_page(_candidate(102)), cursor="older-page")
    result = discovery.run()
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"100", "102"}
    assert len(discovery.requests(api=False)) == 1
    queries = [request["query"] for request in discovery.requests(api=True)]
    assert queries[1]["continue"] == "gcmcontinue||"
    assert queries[1]["gcmcontinue"] == "older-page"
    assert queries[0]["gcmnamespace"] == "6"
    assert queries[0]["gcmsort"] == "timestamp"
    assert queries[0]["gcmdir"] == "older"
    assert "metadata" in queries[0]["iiprop"].split("|")


def test_continuation_survives_separate_runs(discovery: Discovery) -> None:
    """A later process resumes the full server cursor instead of page one."""
    continuation = {"continue": "gcmcontinue||", "gcmcontinue": "next-page"}
    discovery.route(_page(_candidate(100), continuation=continuation))
    discovery.route(_page(_candidate(101)), cursor="next-page")
    first = discovery.run()
    assert first.returncode == 0, first.stderr
    assert discovery.state()["cursors"][CATEGORY] == continuation
    assert discovery.images() == {"100"}
    second = discovery.run()
    assert second.returncode == 0, second.stderr
    assert discovery.images() == {"100", "101"}
    assert discovery.requests(api=True)[1]["query"]["gcmcontinue"] == "next-page"


def test_exhausted_category_checks_for_new_additions(discovery: Discovery) -> None:
    """Completing a category permits discovery of additions on the next cycle."""
    discovery.route(_page(_candidate(100)))
    assert discovery.run().returncode == 0
    discovery.route(_page(_candidate(101), _candidate(100)))
    result = discovery.run()
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"100", "101"}
    assert len(discovery.requests(api=False)) == 2  # ruff: ignore[magic-value-comparison] - expected HTTP request budget


def test_categories_rotate_between_runs(discovery: Discovery) -> None:
    """A large mountain category cannot starve another configured source."""
    discovery.route(_page(_candidate(100)))
    discovery.route(
        _page(_candidate(101, category=COAST_CATEGORY)), category=COAST_CATEGORY
    )
    options = {"categoriesJson": _routes(CATEGORY, COAST_CATEGORY)}
    assert discovery.run(**options).returncode == 0
    result = discovery.run(**options)
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"100", "101"}
    assert [
        request["query"]["gcmtitle"] for request in discovery.requests(api=True)
    ] == [
        "Category:" + CATEGORY,
        "Category:" + COAST_CATEGORY,
    ]


def test_eviction_preserves_current_and_does_not_redownload_seen(
    discovery: Discovery,
) -> None:
    """Eviction respects the displayed file and keeps acquisition history."""
    current = discovery.cache(100)
    old = discovery.cache(101)
    os.utime(current, (1, 1))
    os.utime(old, (2, 2))
    (discovery.root / "state/current").write_text(str(current))
    (discovery.root / "state/commons-discovery.json").write_text(
        json.dumps({
            "version": 1,
            "nextCategory": 0,
            "cursors": {},
            "seen": ["100", "101"],
        })
    )
    discovery.route(_page(_candidate(102)))
    assert discovery.run(maxImages="2").returncode == 0
    assert discovery.images() == {"100", "102"}
    assert not Path(str(old) + ".json").exists()
    discovery.route(_page(_candidate(101), _candidate(103)))
    result = discovery.run(maxImages="2")
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"100", "103"}
    assert len(discovery.requests(api=False)) == 2  # ruff: ignore[magic-value-comparison] - expected HTTP request budget
    assert {"100", "101", "102", "103"} <= set(discovery.state()["seen"])


def test_page_budget_saves_progress(discovery: Discovery) -> None:
    """A run stops at its API budget and saves the next unvisited page."""
    discovery.route(
        _page(
            _candidate(100, camera=False),
            continuation={"continue": "-||", "gcmcontinue": "two"},
        )
    )
    discovery.route(
        _page(
            _candidate(101, camera=False),
            continuation={"continue": "-||", "gcmcontinue": "three"},
        ),
        cursor="two",
    )
    discovery.route(_page(_candidate(102)), cursor="three")
    result = discovery.run(maxCandidatePages="2")
    assert result.returncode == 0, result.stderr
    assert discovery.images() == set()
    assert len(discovery.requests(api=True)) == 2  # ruff: ignore[magic-value-comparison] - expected HTTP request budget
    assert discovery.requests(api=False) == []
    assert discovery.state()["cursors"][CATEGORY]["gcmcontinue"] == "three"
    result = discovery.run(maxCandidatePages="2")
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"102"}


def test_download_budget_bounds_bad_decoded_candidates(discovery: Discovery) -> None:
    """Misleading API dimensions cannot cause unlimited image downloads."""
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - isolated image fixture
        [
            discovery.magick,
            "-size",
            "216x384",
            "xc:steelblue",
            str(discovery.root / "original.jpg"),
        ],
        check=True,
    )
    discovery.route(_page(*(_candidate(identifier) for identifier in range(100, 104))))
    result = discovery.run(maxCandidateDownloads="2")
    assert result.returncode == 0, result.stderr
    assert discovery.images() == set()
    assert len(discovery.requests(api=False)) == 2  # ruff: ignore[magic-value-comparison] - expected HTTP request budget


@pytest.mark.parametrize(
    "failure", ["HTTP failure", {"error": {"code": "maxlag", "info": "Try later"}}]
)
def test_api_failure_preserves_progress_and_cache(
    discovery: Discovery, failure: dict[str, object] | str
) -> None:
    """Transport and API errors are visible failures without losing progress."""
    existing = discovery.cache(100)
    before = existing.read_bytes()
    progress = {
        "version": 1,
        "nextCategory": 0,
        "cursors": {CATEGORY: {"continue": "-||", "gcmcontinue": "resume"}},
        "seen": ["100"],
    }
    state_path = discovery.root / "state/commons-discovery.json"
    state_path.write_text(json.dumps(progress))
    discovery.route(failure, cursor="resume")
    result = discovery.run()
    assert result.returncode != 0
    assert discovery.state()["cursors"] == progress["cursors"]
    assert discovery.state()["seen"] == progress["seen"]
    assert existing.read_bytes() == before
    assert discovery.images() == {"100"}
    assert discovery.requests(api=False) == []


@pytest.mark.parametrize(
    "candidate",
    [
        _candidate(100, title="File:Oil painting of mountain scenery.jpg"),
        _candidate(100, title="File:Historical manuscript of mountain travel.jpg"),
        _candidate(100, featured=False),
        _candidate(100, camera=False),
        _candidate(100, category="Featured pictures of architecture"),
    ],
    ids=["painting", "manuscript", "not-featured", "no-camera", "wrong-category"],
)
def test_unsuitable_content_never_downloads(
    discovery: Discovery, candidate: dict[str, object]
) -> None:
    """Natural-category membership alone cannot admit documents or artwork."""
    discovery.route(_page(candidate))
    result = discovery.run()
    assert result.returncode == 0, result.stderr
    assert discovery.images() == set()
    assert discovery.requests(api=False) == []


def test_failed_category_does_not_starve_other_categories(discovery: Discovery) -> None:
    """A failed provider category retains its cursor and yields the next run."""
    cursor = {"continue": "-||", "gcmcontinue": "resume"}
    (discovery.root / "state/commons-discovery.json").write_text(
        json.dumps({
            "version": 1,
            "nextCategory": 0,
            "cursors": {CATEGORY: cursor},
            "seen": [],
        })
    )
    discovery.route({"error": {"code": "maxlag", "info": "Try later"}}, cursor="resume")
    discovery.route(
        _page(_candidate(101, category=COAST_CATEGORY)), category=COAST_CATEGORY
    )
    options = {"categoriesJson": _routes(CATEGORY, COAST_CATEGORY)}
    first = discovery.run(**options)
    assert first.returncode != 0
    assert discovery.state()["cursors"][CATEGORY] == cursor
    second = discovery.run(**options)
    assert second.returncode == 0, second.stderr
    assert discovery.images() == {"101"}
    assert discovery.state()["cursors"][CATEGORY] == cursor
    assert [
        request["query"]["gcmtitle"] for request in discovery.requests(api=True)
    ] == [
        "Category:" + CATEGORY,
        "Category:" + COAST_CATEGORY,
    ]


def test_local_publication_failure_is_reported_and_retryable(
    discovery: Discovery,
) -> None:
    """An install error must fail without recording acquisition or consuming its page."""
    cursor = {"continue": "-||", "gcmcontinue": "resume"}
    (discovery.root / "state/commons-discovery.json").write_text(
        json.dumps({
            "version": 1,
            "nextCategory": 0,
            "cursors": {CATEGORY: cursor},
            "seen": [],
        })
    )
    install = discovery.root / "bin/install"
    install.write_text(
        "#!" + discovery.bash + "\nprintf 'fixture install failure\\n' >&2\nexit 73\n"
    )
    install.chmod(0o700)
    discovery.route(
        _page(
            _candidate(100), continuation={"continue": "-||", "gcmcontinue": "later"}
        ),
        cursor="resume",
    )
    result = discovery.run(maxCandidatePages="1")
    assert "fixture install failure" in result.stderr
    assert result.returncode != 0
    assert discovery.images() == set()
    assert discovery.state()["seen"] == []
    assert discovery.state()["cursors"][CATEGORY] == cursor
    install.unlink()
    result = discovery.run(maxCandidatePages="1")
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"100"}


@pytest.mark.parametrize(
    "other_category", ["Featured pictures of boats", "Animal photography"]
)
def test_natural_category_does_not_override_unwanted_subject(
    discovery: Discovery, other_category: str
) -> None:
    """A camera photograph in a natural category can still depict unwanted subjects."""
    discovery.route(_page(_candidate(100, category=CATEGORY + "|" + other_category)))
    result = discovery.run()
    assert result.returncode == 0, result.stderr
    assert discovery.images() == set()
    assert discovery.requests(api=False) == []


def test_expired_cursor_resets_only_failed_category(discovery: Discovery) -> None:
    """An expired cursor fails visibly and leaves other category progress usable."""
    mountain_cursor = {"continue": "-||", "gcmcontinue": "expired"}
    coast_cursor = {"continue": "-||", "gcmcontinue": "coast-resume"}
    (discovery.root / "state/commons-discovery.json").write_text(
        json.dumps({
            "version": 1,
            "nextCategory": 0,
            "cursors": {CATEGORY: mountain_cursor, COAST_CATEGORY: coast_cursor},
            "seen": ["100"],
        })
    )
    discovery.route(
        {"error": {"code": "badcontinue", "info": "Invalid continue parameter"}},
        cursor="expired",
    )
    discovery.route(
        _page(_candidate(101, category=COAST_CATEGORY)),
        category=COAST_CATEGORY,
        cursor="coast-resume",
    )
    options = {"categoriesJson": _routes(CATEGORY, COAST_CATEGORY)}
    first = discovery.run(**options)
    assert first.returncode != 0
    assert discovery.state()["cursors"].get(CATEGORY, {}) == {}
    assert discovery.state()["cursors"][COAST_CATEGORY] == coast_cursor
    assert discovery.state()["seen"] == ["100"]
    second = discovery.run(**options)
    assert second.returncode == 0, second.stderr
    assert discovery.images() == {"101"}
    assert discovery.requests(api=True)[1]["query"]["gcmcontinue"] == "coast-resume"


def test_malformed_record_cannot_block_later_page(discovery: Discovery) -> None:
    """A malformed file record is skipped while valid API continuation is retained."""
    malformed = _candidate(100)
    info = malformed["imageinfo"]
    assert isinstance(info, list)
    info[0]["extmetadata"] = ["not an object"]
    discovery.route(
        _page(
            malformed,
            continuation={"gcmcontinue": "later", "continue": "gcmcontinue||"},
        )
    )
    discovery.route(_page(_candidate(101)), cursor="later")
    result = discovery.run()
    assert result.returncode == 0, result.stderr
    assert discovery.images() == {"101"}
