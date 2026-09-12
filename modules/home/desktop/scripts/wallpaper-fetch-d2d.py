"""Acquire licensed observational astronomy wallpapers from ESA's Data2Dome feeds."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import random
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] - bounded curl and image conversion commands
import sys
import tempfile
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qs, urlparse

LICENSE = "Creative Commons Attribution 4.0 International License"
SOURCE_CATEGORIES = {
    "nebulae": "nebulae",
    "galaxies": "galaxies",
    "stars": "stars",
    "clusters": "stars",
    "solarsystem": "solar-system",
}
UNWANTED_TITLE = re.compile(
    r"\b(artwork|artist.s (impression|concept)|illustration|simulation|diagram|chart|"
    r"spectra|spectrum|annotated|comparison|collage|calendar|cover|poster|"
    r"panels?|inset|infographic|compass|scale bar)\b",
    re.IGNORECASE,
)
UNWANTED_DESCRIPTION = re.compile(
    r"\b(panels?|inset|labels?|labelled|labeled|annotated|scale bar|diagram|"
    r"collage|illustration|artist.s (impression|concept))\b",
    re.IGNORECASE,
)
MAX_MEDIA_BYTES = 150 * 1024 * 1024
MAX_PIXELS = 100000000
MAX_CURSOR_PAGE = 10000
MIN_PRIORITY = 80
MAX_FEED_ITEMS = 100
# The service has a five-minute timeout; leave time for failure reporting.
DEADLINE = time.monotonic() + 240


@dataclass(frozen=True)
class Connection:
    """The owned hosts and cache prefix of one official image provider."""

    host: str
    prefix: str

    @property
    def feed(self) -> str:
        """The provider's current discovery feed.

        Returns:
            HTTPS first-page endpoint.

        """
        return f"https://{self.host}/images/d2d/"


CONNECTIONS = {
    "esaHubble": Connection("esahubble.org", "esa-hubble-"),
    "esaWebb": Connection("esawebb.org", "esa-webb-"),
}


class ObjectCategories(HTMLParser):
    """Read image categories only from the About the Object table's category row."""

    def __init__(self) -> None:
        """Start outside the image metadata table."""
        super().__init__()
        self.in_table = False
        self.in_heading = False
        self.heading = ""
        self.categories: set[str] = set()
        self.excluded = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        """Track the object table and its row heading."""
        attributes = dict(attrs)
        if tag == "table":
            self.in_table = attributes.get("aria-describedby") == "About the Object"
        if not self.in_table:
            return
        if tag == "tr":
            self.heading = ""
        if tag == "th":
            self.in_heading = True
        if tag == "a" and self.heading.strip() == "Category:":
            path = attributes.get("href") or ""
            match = re.fullmatch(r"/images/archive/category/([a-z]+)/", path)
            if match and match[1] in {
                "graphics",
                "illustrations",
                "spacecraft",
                "spectroscopy",
                "launch",
            }:
                self.excluded = True
            if match and match[1] in SOURCE_CATEGORIES:
                self.categories.add(SOURCE_CATEGORIES[match[1]])

    def handle_endtag(self, tag: str) -> None:
        """Stop collecting headings or object-table content at their boundary."""
        if tag == "th":
            self.in_heading = False
        if tag == "table":
            self.in_table = False

    def handle_data(self, data: str) -> None:
        """Accumulate the current row label."""
        if self.in_table and self.in_heading:
            self.heading += data


def _remaining(maximum: int) -> float:
    remaining = DEADLINE - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("Astronomy acquisition exceeded its four-minute budget")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic
    return min(maximum, remaining)


def _fetch(url: str, destination: Path, limit: int) -> None:
    remaining = _remaining(145)
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - fixed curl flags and validated HTTPS URLs
        [  # ruff: ignore[start-process-with-partial-path] - executables come from the pinned runtime PATH
            "curl",
            "--fail",
            "--silent",
            "--show-error",
            "--proto",
            "=https",
            "--tlsv1.2",
            "--connect-timeout",
            "10",
            "--max-time",
            str(min(60, remaining)),
            "--retry",
            "1",
            "--retry-delay",
            "2",
            "--retry-max-time",
            str(min(70, remaining)),
            "--max-filesize",
            str(limit),
            "--user-agent",
            "desktop-wallpaper/1.0 (ESA Data2Dome landscape image client)",
            "--output",
            str(destination),
            url,
        ],
        check=True,
        capture_output=True,
        timeout=remaining,
    )
    if destination.stat().st_size > limit:
        raise ValueError("Provider response exceeded the transfer limit")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic


def _feed_url(url: str, connection: Connection) -> bool:
    parsed = urlparse(url)
    query = parse_qs(parsed.query)
    return (
        parsed.scheme == "https"
        and parsed.netloc == connection.host
        and parsed.path == "/images/d2d/"
        and not parsed.fragment
        and set(query) <= {"page"}
        and all(
            len(values) == 1
            and values[0].isdigit()
            and 0 < int(values[0]) <= MAX_CURSOR_PAGE
            for values in query.values()
        )
    )


def _geometry(width: int, height: int, target_width: int, target_height: int) -> bool:
    return (
        width >= target_width
        and height >= target_height
        and width * height <= MAX_PIXELS
        and width * target_height * 5 >= height * target_width * 4
        and width * target_height * 4 <= height * target_width * 5
    )


def _resource(  # ruff: ignore[complex-structure, too-many-return-statements, too-many-branches] - explicit independent provider admission gates
    item: dict, connection: Connection, width: int, height: int
) -> dict | None:
    if (
        item.get("Rights") != LICENSE
        or not item.get("Credit")
        or item.get("Priority", 0) < MIN_PRIORITY
    ):
        return None
    identifier = item.get("ID", "")
    if not isinstance(identifier, str) or not re.fullmatch(
        r"[a-zA-Z0-9_-]+", identifier
    ):
        return None
    if item.get("ReferenceURL") != f"https://{connection.host}/images/{identifier}/":
        return None
    title = item.get("Title", "")
    if not isinstance(title, str) or UNWANTED_TITLE.search(title):
        return None
    # Science captions routinely discuss other observations or comparison images.
    # The accessibility description describes the actual visible composition.
    description = re.sub(r"<[^>]*>", "", item.get("Description", ""))
    visible = re.search(
        r"\[\s*Image Description\s*:(.*?)\]", description, re.IGNORECASE | re.DOTALL
    )
    if visible and UNWANTED_DESCRIPTION.search(visible[1]):
        return None
    for asset in item.get("Assets", []):
        observation = asset.get("ObservationData", {})
        if (
            asset.get("MediaType") != "Image"
            or not observation.get("Facility")
            or not observation.get("Instrument")
        ):
            continue
        for resource in asset.get("Resources", []):
            if (
                resource.get("ResourceType") != "Large"
                or resource.get("MediaType") != "Image"
                or resource.get("ProjectionType") != "Observation"
            ):
                continue
            url = resource.get("URL", "")
            expected_url = (
                f"https://cdn.{connection.host}/archives/images/large/{identifier}.jpg"
            )
            if url != expected_url:
                continue
            dimensions = resource.get("Dimensions", [])
            if len(dimensions) != 2 or not all(  # ruff: ignore[magic-value-comparison] - fixed image metadata tuple shape
                isinstance(value, int) and value > 0 for value in dimensions
            ):
                continue
            size = resource.get("FileSize", 0)
            if not isinstance(size, int) or not 0 < size <= MAX_MEDIA_BYTES:
                continue
            if _geometry(dimensions[0], dimensions[1], width, height):
                return resource
    return None


def _save_state(path: Path, state: dict) -> None:
    temporary = path.with_suffix(".pending")
    try:
        temporary.write_text(json.dumps(state) + "\n", encoding="utf-8")
        temporary.chmod(0o600)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _load_state(path: Path, connection: Connection) -> dict:
    if not path.exists():
        return {"version": 1, "cursor": connection.feed, "seen": []}
    state = json.loads(path.read_text(encoding="utf-8"))
    if (
        not isinstance(state, dict)  # ruff: ignore[too-many-boolean-expressions] - validate persisted state fields before network access
        or state.get("version") != 1
        or not isinstance(state.get("cursor"), str)
        or not _feed_url(state["cursor"], connection)
        or not isinstance(state.get("seen"), list)
        or not all(isinstance(identifier, str) for identifier in state["seen"])
    ):
        raise ValueError("Invalid astronomy discovery state")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic
    return state


def _render(original: Path, display: Path, width: int, height: int) -> bool:
    identified = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - bounded local image inspection
        [  # ruff: ignore[start-process-with-partial-path] - executables come from the pinned runtime PATH
            "magick",
            "identify",
            "-ping",
            "-format",
            "%w %h %[orientation] %m",
            str(original),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=_remaining(30),
    ).stdout.split()
    if len(identified) != 4 or identified[3] not in {"JPEG", "PNG", "TIFF", "WEBP"}:  # ruff: ignore[magic-value-comparison] - fixed image metadata tuple shape
        return False
    decoded_width, decoded_height = int(identified[0]), int(identified[1])
    if identified[2] in {"LeftTop", "RightTop", "RightBottom", "LeftBottom"}:
        decoded_width, decoded_height = decoded_height, decoded_width
    if not _geometry(decoded_width, decoded_height, width, height):
        return False
    subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - bounded local image conversion
        [  # ruff: ignore[start-process-with-partial-path] - executables come from the pinned runtime PATH
            "magick",
            "-limit",
            "memory",
            "256MiB",
            "-limit",
            "map",
            "512MiB",
            "-limit",
            "disk",
            "1GiB",
            str(original),
            "-auto-orient",
            "-colorspace",
            "sRGB",
            "-resize",
            f"{width}x{height}^",
            "-gravity",
            "center",
            "-extent",
            f"{width}x{height}",
            "-strip",
            "-sampling-factor",
            "4:4:4",
            "-quality",
            "95",
            str(display),
        ],
        check=True,
        capture_output=True,
        timeout=_remaining(120),
    )
    return True


def _prune(directory: Path, state_directory: Path, prefix: str, maximum: int) -> None:
    current_path = state_directory / "current"
    current = (
        current_path.read_text(encoding="utf-8").strip()
        if current_path.exists()
        else ""
    )
    images = sorted(
        directory.glob(prefix + "*.jpg"), key=lambda path: path.stat().st_mtime_ns
    )
    excess = len(images) - maximum
    for image in images:
        if excess <= 0:
            break
        if str(image) != current:
            image.unlink()
            Path(str(image) + ".json").unlink(missing_ok=True)
            excess -= 1


def _discover(args: argparse.Namespace, enabled: set[str]) -> int:  # ruff: ignore[too-many-locals, complex-structure, too-many-statements, too-many-branches] - one bounded discovery transaction
    connection = CONNECTIONS[args.connection]
    state_path = args.state / (connection.prefix + "discovery.json")
    state = _load_state(state_path, connection)
    inspections = 0
    with tempfile.TemporaryDirectory(prefix=".d2d-", dir=args.directory) as temporary:
        scratch = Path(temporary)
        for _ in range(args.max_pages):
            page_file = scratch / "page.json"
            _fetch(state["cursor"], page_file, 10 * 1024 * 1024)
            page = json.loads(page_file.read_text(encoding="utf-8"))
            if (
                not isinstance(page, dict)
                or not isinstance(page.get("Collections"), list)
                or len(page["Collections"]) > MAX_FEED_ITEMS
            ):
                raise ValueError("Invalid Data2Dome feed response")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic
            next_url = page.get("Next") or connection.feed
            if not isinstance(next_url, str) or not _feed_url(next_url, connection):
                raise ValueError("Invalid Data2Dome continuation URL")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic
            candidates = list(page["Collections"])
            random.shuffle(candidates)
            for item in candidates:
                try:
                    resource = _resource(item, connection, args.width, args.height)
                except (TypeError, ValueError, KeyError, AttributeError):
                    # Skip malformed records without consuming the rest of the feed.
                    print("Skipping malformed astronomy metadata.", file=sys.stderr)  # ruff: ignore[print] - bounded CLI diagnostic
                    continue
                if resource is None or item["ID"] in state["seen"]:
                    continue
                identifier = item["ID"]
                if list(
                    args.directory.glob(
                        f"{connection.prefix}{identifier}-{args.width}x{args.height}-*.jpg"
                    )
                ):
                    state["seen"] = (state["seen"] + [identifier])[-10000:]
                    continue
                if inspections >= args.max_downloads:
                    break
                inspections += 1
                detail = scratch / "detail.html"
                _fetch(item["ReferenceURL"], detail, 2 * 1024 * 1024)
                parser = ObjectCategories()
                parser.feed(detail.read_text(encoding="utf-8"))
                categories = parser.categories
                if parser.excluded or not categories & enabled:
                    continue
                original, display = scratch / "original", scratch / "display.jpg"
                _fetch(resource["URL"], original, MAX_MEDIA_BYTES)
                try:
                    rendered = _render(original, display, args.width, args.height)
                except subprocess.CalledProcessError:
                    # Transport, timeouts and publication still fail visibly.
                    # Decoder rejection is unsuitable content, like wrong geometry.
                    print("Skipping an invalid astronomy image.", file=sys.stderr)  # ruff: ignore[print] - bounded CLI diagnostic
                    continue
                if not rendered:
                    continue
                with display.open("rb") as stream:
                    checksum = hashlib.file_digest(stream, "sha256").hexdigest()
                destination = (
                    args.directory
                    / f"{connection.prefix}{identifier}-{args.width}x{args.height}-{checksum}.jpg"
                )
                sidecar = Path(str(destination) + ".json")
                metadata = {
                    "connection": args.connection,
                    "wallpaper_categories": [
                        "space/" + category for category in sorted(categories)
                    ],
                    "source": item.get("Creator", args.connection),
                    "source_id": identifier,
                    "source_page": item["ReferenceURL"],
                    "title": item["Title"],
                    "credit": item["Credit"],
                    "license": "CC BY 4.0",
                    "license_url": "https://creativecommons.org/licenses/by/4.0/",
                    "url": resource["URL"],
                    "original_width": resource["Dimensions"][0],
                    "original_height": resource["Dimensions"][1],
                    "width": args.width,
                    "height": args.height,
                    "sha256": checksum,
                    "retrieved_at": datetime.now(UTC).isoformat(),
                    "conversion": "Centered crop and downsample to sRGB JPEG",
                }
                metadata_file = scratch / "metadata.json"
                metadata_file.write_text(json.dumps(metadata) + "\n", encoding="utf-8")
                metadata_file.chmod(0o600)
                display.chmod(0o600)
                try:
                    metadata_file.replace(sidecar)
                    display.replace(destination)
                    state["seen"] = (state["seen"] + [identifier])[-10000:]
                    state["cursor"] = next_url
                    _save_state(state_path, state)
                except OSError:
                    destination.unlink(missing_ok=True)
                    sidecar.unlink(missing_ok=True)
                    raise
                _prune(args.directory, args.state, connection.prefix, args.max_images)
                print(  # ruff: ignore[print] - CLI status output
                    f"Added {args.connection} {identifier}: {', '.join(metadata['wallpaper_categories'])}"
                )
                return 0
            state["cursor"] = next_url
            _save_state(state_path, state)
            if next_url == connection.feed or inspections >= args.max_downloads:
                break
    print(f"No new qualifying {args.connection} wallpaper; discovery progress saved.")  # ruff: ignore[print] - CLI status
    return 0


def _acquire(args: argparse.Namespace) -> int:
    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    if not isinstance(plan, list) or not all(isinstance(route, dict) for route in plan):
        raise ValueError("Invalid wallpaper connection plan")  # ruff: ignore[raise-vanilla-args, raw-string-in-exception] - CLI diagnostic
    enabled = {
        route["subcategory"]
        for route in plan
        if route.get("connection") == args.connection
        and route.get("category") == "space"
        and route.get("subcategory") in SOURCE_CATEGORIES.values()
    }
    if not enabled:
        return 0
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    args.state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (args.state / (CONNECTIONS[args.connection].prefix + "fetch.lock")).open(
        "a", encoding="utf-8"
    ) as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        return _discover(args, enabled)


def main() -> int:
    """Run one bounded acquisition for an enabled connection.

    Returns:
        Zero for success or disabled acquisition, nonzero for operational failures.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection", choices=CONNECTIONS, required=True)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    for name, default in [
        ("width", 3840),
        ("height", 2160),
        ("max-images", 30),
        ("max-pages", 3),
        ("max-downloads", 3),
    ]:
        parser.add_argument("--" + name, type=int, default=default)
    args = parser.parse_args()
    if any(
        getattr(args, name) <= 0
        for name in ["width", "height", "max_images", "max_pages", "max_downloads"]
    ):
        parser.error("Dimensions and acquisition limits must be positive")
    try:
        return _acquire(args)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.SubprocessError,
    ) as error:
        print(  # ruff: ignore[print] - CLI status output
            f"Astronomy wallpaper acquisition failed: {error}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
