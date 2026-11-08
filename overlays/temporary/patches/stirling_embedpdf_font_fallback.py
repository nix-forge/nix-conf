"""Keep EmbedPDF 2.15's Latin font fallbacks faithful to the requested face.

The upstream NPM package only matches charset, weight and italic. Stirling's
local default is Noto Sans, so unembedded Times and Courier render incorrectly.
Patch the installed dependency before Vite bundles or compresses the viewer.
"""

# Build failures must name the unexpected pinned dependency. This short-lived
# build helper does not need a public exception class for each guard.
# ruff: file-ignore[raise-vanilla-args, f-string-in-exception, raw-string-in-exception, docstring-missing-exception]

import sys
from hashlib import sha256
from pathlib import Path

EXPECTED = {
    "direct-engine-C8xTbxym.js": "f87c5fd5b58ba1b5aadeb21ae895af15cc6539ea226ff2920396c3bbff1f4daa",
    "worker-engine.js": "270638a8a5b91dd442245196b372230b577eef4953b6e7088fe867355dc17114",
}

BEFORE = "    const result = this.findBestFontMatch(charset, weight, italic);\n"
AFTER = BEFORE + Path(sys.argv[2]).read_text(encoding="utf-8")


def patch(path: Path, *, escaped: bool) -> None:
    """Patch one checked EmbedPDF module."""
    data = path.read_bytes()
    actual = sha256(data).hexdigest()
    if actual != EXPECTED[path.name]:
        raise RuntimeError(f"EmbedPDF source changed: {path.name} ({actual})")

    before = BEFORE.replace("\n", "\\n") if escaped else BEFORE
    after = AFTER.replace("\n", "\\n") if escaped else AFTER
    source = data.decode("utf-8")
    if source.count(before) != 1 or source.count("      url: result.url,") != 1:
        raise RuntimeError(f"Unexpected EmbedPDF font mapping: {path.name}")
    source = source.replace(before, after, 1)
    url_before = "      url: result.url,"
    url_after = "      url: selectedUrl,"
    source = source.replace(url_before, url_after, 1)
    path.write_text(source, encoding="utf-8")


def main(root: Path) -> None:
    """Patch both EmbedPDF execution paths in an installed node_modules tree."""
    dist = root / "@embedpdf" / "engines" / "dist"
    direct = list(dist.glob("direct-engine-*.js"))
    if len(direct) != 1 or direct[0].name not in EXPECTED:
        raise RuntimeError("Unexpected EmbedPDF direct engine files")
    patch(direct[0], escaped=False)
    patch(dist / "lib/pdfium/web/worker-engine.js", escaped=True)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
