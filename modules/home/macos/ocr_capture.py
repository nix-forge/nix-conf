"""Interactive macOS screenshot OCR helper for Home Manager."""

from __future__ import annotations

import contextlib
import os
import re
import subprocess  # noqa: S404
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence

SWIFT_SOURCE = "__SWIFT_SOURCE__"
CLEANUP_MODE = "__CLEANUP_MODE__"
MAX_BLANK_LINES = 2
MIN_HYPHEN_PREFIX_LEN = 2
CODEISH_PUNCT_THRESHOLD = 2

LIST_MARKER_RE = re.compile(r"^(\s*(?:[-*+•◦▪‣]|(?:\d+|[A-Za-z])[.)]))\s+(.*\S)?\s*$")
URLISH_RE = re.compile(
    r"(https?://|www\.|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"
)
CODEISH_RE = re.compile(
    r"^\s*(?:[$>#]|[A-Za-z0-9_./-]+\s*[:=]\s*\S|.+[{}[\]();`].*|.+\s->\s.+|.+::.+)\s*$"
)


class OCRCaptureError(RuntimeError):
    """Base error for the OCR capture helper."""


class SwiftToolchainError(OCRCaptureError):
    """Raised when the Apple Swift toolchain is unavailable."""

    def __init__(self) -> None:
        """Initialize the fixed user-facing guidance for a missing Swift toolchain."""
        super().__init__(
            "Install Xcode Command Line Tools or Xcode to enable OCR capture."
        )


class CaptureCommandError(OCRCaptureError):
    """Raised when the interactive screenshot command fails unexpectedly."""


class OCRCommandError(OCRCaptureError):
    """Raised when the Swift OCR helper exits unsuccessfully."""


def _notify(title: str, body: str) -> None:
    env = os.environ.copy()
    env["HM_OCR_TITLE"] = title
    env["HM_OCR_BODY"] = body
    script = (
        'display notification (system attribute "HM_OCR_BODY") '
        'with title (system attribute "HM_OCR_TITLE")'
    )
    subprocess.run(  # noqa: S603
        ["/usr/bin/osascript", "-e", script],
        check=False,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _fail(message: str, *, details: str | None = None) -> int:
    body = message if details is None else f"{message}: {details}"
    _notify("OCR capture failed", body)
    sys.stderr.write(f"{body}\n")
    return 1


def _run_capture(image_path: Path) -> bool:
    proc = subprocess.run(  # noqa: S603
        ["/usr/sbin/screencapture", "-i", "-s", "-x", str(image_path)],
        capture_output=True,
        text=True,
        check=False,
    )

    if proc.returncode == 0 and image_path.exists() and image_path.stat().st_size > 0:
        return True

    stderr = (proc.stderr or proc.stdout or "").strip()
    if (not image_path.exists() or image_path.stat().st_size == 0) and not stderr:
        return False
    if "cancel" in stderr.lower():
        return False

    raise CaptureCommandError(stderr or "Screen capture did not complete.")


def _ensure_swift() -> None:
    proc = subprocess.run(
        ["/usr/bin/xcrun", "--find", "swift"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SwiftToolchainError


def _run_ocr(image_path: Path) -> str:
    _ensure_swift()
    proc = subprocess.run(  # noqa: S603
        ["/usr/bin/xcrun", "swift", SWIFT_SOURCE, str(image_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        raise OCRCommandError(
            stderr or "Vision OCR helper exited with a non-zero status."
        )
    return proc.stdout


def _is_list_item(line: str) -> bool:
    return bool(LIST_MARKER_RE.match(line))


def _is_urlish(line: str) -> bool:
    return bool(URLISH_RE.search(line))


def _is_codeish(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.startswith(("```", "~~~")):
        return True
    if CODEISH_RE.match(line):
        return True
    punctuation = sum(1 for char in stripped if char in "{}[]();`<>")
    return punctuation >= CODEISH_PUNCT_THRESHOLD and " " not in stripped


def _squeeze_spaces(text: str) -> str:
    return re.sub(r"[ \t]+", " ", text.strip())


def _join_fragments(lines: Sequence[str]) -> str:
    result = ""

    for line in lines:
        fragment = _squeeze_spaces(line)
        if not fragment:
            continue

        if not result:
            result = fragment
            continue

        has_hyphen_suffix = result.endswith("-")
        has_minimum_prefix = len(result) >= MIN_HYPHEN_PREFIX_LEN
        prefix_char_is_alpha = (
            result[-MIN_HYPHEN_PREFIX_LEN].isalpha() if has_minimum_prefix else False
        )
        has_alpha_prefix = has_minimum_prefix and prefix_char_is_alpha
        next_fragment_continues_word = fragment[0].islower()
        should_merge_hyphenation = (
            has_hyphen_suffix and has_alpha_prefix and next_fragment_continues_word
        )
        if should_merge_hyphenation:
            result = result[:-1] + fragment
            continue

        separator = ""
        if not fragment.startswith((",", ".", ":", ";", ")", "]", "}", "%", "'")):
            separator = " "

        result = f"{result}{separator}{fragment}"

    return result


def _normalize_text(text: str) -> str:
    return unicodedata.normalize("NFKC", text).replace("\r\n", "\n").replace("\r", "\n")


def _cleanup_minimal(text: str) -> str:
    lines = [line.strip() for line in _normalize_text(text).split("\n")]
    return "\n".join(line for line in lines if line).strip()


def _compact_blank_lines(lines: Sequence[str]) -> list[str]:
    compacted: list[str] = []
    blank_run = 0
    for line in lines:
        if not line:
            blank_run += 1
            if blank_run <= MAX_BLANK_LINES:
                compacted.append("")
            continue
        blank_run = 0
        compacted.append(line)
    return compacted


def _split_blocks(lines: Sequence[str]) -> list[list[str]]:
    blocks: list[list[str]] = []
    current: list[str] = []
    for line in lines:
        if not line:
            if current:
                blocks.append(current)
                current = []
            continue
        current.append(line)
    if current:
        blocks.append(current)
    return blocks


def _split_list_items(block: Sequence[str]) -> list[list[str]]:
    items: list[list[str]] = []
    current_item: list[str] = []
    for line in block:
        if _is_list_item(line):
            if current_item:
                items.append(current_item)
            current_item = [line]
        else:
            current_item.append(line)
    if current_item:
        items.append(current_item)
    return items


def _render_list_block(block: Sequence[str]) -> str:
    rendered_items: list[str] = []
    for item in _split_list_items(block):
        match = LIST_MARKER_RE.match(item[0])
        if match is None:
            rendered_items.append("\n".join(item))
            continue
        marker = match.group(1).strip()
        first_text = match.group(2) or ""
        rendered_items.append(
            f"{marker} {_join_fragments([first_text, *item[1:]])}".rstrip()
        )
    return "\n".join(rendered_items)


def _render_block(block: Sequence[str]) -> str:
    if len(block) == 1:
        return block[0]
    if any(_is_codeish(line) or _is_urlish(line) for line in block):
        return "\n".join(block)
    if _is_list_item(block[0]):
        return _render_list_block(block)
    return _join_fragments(block)


def _cleanup_balanced(text: str) -> str:
    raw_lines = [line.strip() for line in _normalize_text(text).split("\n")]
    compacted_lines = _compact_blank_lines(raw_lines)
    blocks = _split_blocks(compacted_lines)
    rendered_blocks = [_render_block(block) for block in blocks]
    return "\n\n".join(block for block in rendered_blocks if block.strip()).strip()


def _clean_text(text: str) -> str:
    if CLEANUP_MODE == "balanced":
        return _cleanup_balanced(text)
    return _cleanup_minimal(text)


def _copy_to_clipboard(text: str) -> None:
    subprocess.run(
        ["/usr/bin/pbcopy"],
        input=text,
        text=True,
        check=True,
    )


def _main() -> int:
    with tempfile.NamedTemporaryFile(
        prefix="hm-ocr-capture-",
        suffix=".png",
        delete=False,
    ) as image_handle:
        image_path = Path(image_handle.name)

    try:
        captured = _run_capture(image_path)
        if not captured:
            return 0

        raw_text = _run_ocr(image_path)
        cleaned = _clean_text(raw_text)
        if not cleaned:
            _notify("OCR capture", "No text recognized.")
            return 0

        _copy_to_clipboard(cleaned)
        _notify("OCR capture", f"Copied {len(cleaned)} characters to the clipboard.")
    except OCRCaptureError as err:
        return _fail("Unable to capture or extract text", details=str(err))
    finally:
        with contextlib.suppress(OSError):
            image_path.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
