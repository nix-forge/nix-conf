#!/usr/bin/env python3
# ruff: file-ignore[suspicious-subprocess-import, subprocess-without-shell-equals-true]
# Fontconfig is queried with argument lists, never a shell.
"""Validate font selection and language shaping; report intentional overlaps."""

import argparse
import collections
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import TypedDict

import uharfbuzz as hb

BOLD_WEIGHT = 180
FACE_INDEX_MASK = 0xFFFF


class FontMatch(TypedDict):
    """Resolved Fontconfig face and requested style characteristics."""

    file: str
    family: str
    index: int
    weight: float
    slant: int


def query_fontconfig(command: str, *args: str) -> str:
    """Return output from an installed Fontconfig utility.

    Returns:
        Its standard output.

    Raises:
        RuntimeError: When the utility is unavailable.

    """
    executable = shutil.which(command)
    if executable is None:
        message = f"Missing Fontconfig utility: {command}"
        raise RuntimeError(message)
    return subprocess.check_output([executable, *args], text=True)


def match(pattern: str) -> FontMatch:
    """Check the font contract.

    Returns:
        The actual file, face and style selected for a pattern.

    """
    file, family, index, weight, slant = query_fontconfig(
        "fc-match", "-f", "%{file}\t%{family}\t%{index}\t%{weight}\t%{slant}", pattern
    ).split("\t")
    return {
        "file": str(Path(file).resolve()),
        "family": family.split(",")[0],
        "index": int(index),
        "weight": float(weight),
        "slant": int(slant),
    }


def check_roles(policy: dict) -> tuple[dict, list]:
    """Check the font contract.

    Returns:
        Selections and failures for the four primary roles.

    """
    results, failures = {}, []
    for generic, expected in policy.items():
        styles = (
            [(False, False)]
            if generic == "emoji"
            else [(False, False), (True, False), (False, True), (True, True)]
        )
        for bold, italic in styles:
            query = f"{generic}:weight={'bold' if bold else 'regular'}:slant={'italic' if italic else 'roman'}"
            actual = match(query)
            results[query] = actual
            provider_ok = actual["family"] in expected["families"] and actual[
                "file"
            ].startswith(expected["package"] + "/")
            style_ok = (actual["weight"] >= BOLD_WEIGHT) == bold and (
                actual["slant"] != 0
            ) == italic
            if not provider_ok or not style_ok:
                failures.append({
                    "query": query,
                    "actual": actual,
                    "expected": expected,
                })
    return results, failures


def check_cjk() -> tuple[list, list]:
    """Check the font contract.

    Returns:
        Regional shaping comparisons and failures with explicit language tags.

    """
    cjk, failures = [], []
    for language in ["ja", "zh-cn", "zh-tw", "ko"]:
        shapes = []
        for family in ["Noto Sans CJK SC", "Noto Sans CJK JP", "Noto Sans CJK TC"]:
            chosen = match(family)
            font = hb.Font(
                hb.Face(
                    Path(chosen["file"]).read_bytes(), chosen["index"] & FACE_INDEX_MASK
                )
            )
            buffer = hb.Buffer()
            buffer.add_str("骨直令漢")
            buffer.guess_segment_properties()
            buffer.language = language
            hb.shape(font, buffer)
            shapes.append([g.codepoint for g in buffer.glyph_infos])
        cjk.append({"language": language, "glyphs": shapes})
        if any(0 in s or s != shapes[0] for s in shapes):
            failures.append({"cjk": language, "shapes": shapes})
    return cjk, failures


def inventory() -> tuple[dict, list]:
    """Check the font contract.

    Returns:
        Physical PostScript providers and unexpected emoji font failures.

    """
    raw = query_fontconfig(
        "fc-list", "-f", "%{file}\t%{postscriptname}\t%{fontversion}\n"
    )
    identities, failures = collections.defaultdict(set), []
    for row in raw.splitlines():
        file, name, version = row.split("\t")
        real = str(Path(file).resolve())
        if "NotoColorEmojiCompatTest" in Path(file).name:
            failures.append({"unexpectedCompatibilityFont": file})
        if name:
            identities[name].add((real, version))
    noto = {path for path, _ in identities.get("NotoColorEmoji", [])}
    if len(noto) != 1:
        failures.append({"notoProviders": sorted(noto)})
    return identities, failures


def main() -> bool:
    """Check the font contract.

    Returns:
        Whether the installed collection violates its selection policy.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--providers", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", action="store_true")
    args = parser.parse_args()
    started = time.perf_counter()
    results, failures = check_roles(json.loads(args.providers.read_text()))
    cjk, cjk_failures = check_cjk()
    identities, identity_failures = inventory()
    failures.extend(cjk_failures + identity_failures)
    report = {"selection": results, "cjk": cjk, "failures": failures}
    if args.inventory:
        paths = {path for providers in identities.values() for path, _ in providers}
        report["inventory"] = {
            "uniqueFiles": len(paths),
            "fontBytes": sum(Path(path).stat().st_size for path in paths),
            "postScriptNames": len(identities),
        }
        report["duplicateIdentities"] = {
            name: [
                {
                    "file": p,
                    "version": v,
                    "sha256": hashlib.sha256(Path(p).read_bytes()).hexdigest(),
                }
                for p, v in sorted(paths)
            ]
            for name, paths in identities.items()
            if len(paths) > 1
        }
    report["elapsedSeconds"] = round(time.perf_counter() - started, 3)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(  # ruff: ignore[print] -- CLI result.
        json.dumps(
            {
                "selections": len(results),
                "cjkLanguages": len(cjk),
                "failures": failures,
            },
            indent=2,
        )
    )
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
