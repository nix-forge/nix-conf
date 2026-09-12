"""Build the selected public guide and verify its source-backed examples."""

from __future__ import annotations

import argparse
import logging
import re
import shutil
import tempfile
from pathlib import Path

from mkdocs.commands.build import build
from mkdocs.config import load_config
from pygments.formatters.html import HtmlFormatter
from reference import insert_reference

INCLUDE = re.compile(
    r"<!-- include: ([\w./-]+) -->\n\n?```(\w+)\n(.*?)```\n\n?<!-- /include -->",
    re.DOTALL,
)


def snippets(source: Path, *, update: bool = False) -> None:
    """Compare explicit example fences with public template source files.

    Raises:
        ValueError: An example is outdated, malformed, or outside the public starter.

    """
    for page in sorted((source / "docs/guide").glob("*.md")):
        text = page.read_text()

        def replace(match: re.Match[str], *, page: Path = page) -> str:
            relative, language, current = match.groups()
            target = (source / relative).resolve()
            if not target.is_relative_to((source / "templates/starter").resolve()):
                message = f"Example source must belong to templates/starter: {relative}"
                raise ValueError(message)
            expected = target.read_text().rstrip() + "\n"
            if not update and current != expected:
                message = f"Outdated example in {page.name}: {relative}; run --update-snippets"
                raise ValueError(message)
            return f"<!-- include: {relative} -->\n\n```{language}\n{expected}```\n\n<!-- /include -->"

        rewritten = INCLUDE.sub(replace, text)
        if text.count("<!-- include:") != len(INCLUDE.findall(text)):
            message = f"Malformed example marker in {page.name}"
            raise ValueError(message)
        if update and text != rewritten:
            page.write_text(rewritten)


def build_guide(
    source: Path, output: Path, catalog: Path | None = None, options: Path | None = None
) -> None:
    """Stage only guide pages and reviewed images, then run strict MkDocs."""
    snippets(source)
    with tempfile.TemporaryDirectory(prefix="nix-conf-guide-") as temporary:
        staged = Path(temporary) / "docs"
        staged.mkdir()
        shutil.copyfile(source / "docs/README.md", staged / "README.md")
        shutil.copytree(source / "docs/guide", staged / "guide")
        if catalog is not None and options is not None:
            insert_reference(staged, catalog, options)
        assets = staged / "assets/font-implementation"
        assets.mkdir(parents=True)
        for name in ("pango.png", "qt.png"):
            shutil.copyfile(
                source / "docs/assets/font-implementation" / name, assets / name
            )
        styles = staged / "stylesheets"
        styles.mkdir()
        shutil.copyfile(source / "site/guide.css", styles / "guide.css")
        (styles / "code.css").write_text(
            HtmlFormatter(style="friendly").get_style_defs(".codehilite")
        )
        config = load_config(
            config_file=str(source / "site/mkdocs.yml"),
            docs_dir=str(staged),
            site_dir=str(output),
            strict=True,
        )
        build(config)


def main() -> None:
    """Run a reproducible build or explicitly synchronize embedded examples."""
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", type=Path, default=Path(__file__).resolve().parent.parent
    )
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--update-snippets", action="store_true")
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--options", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    if args.update_snippets:
        snippets(source, update=True)
    else:
        build_guide(source, args.output.resolve(), args.catalog, args.options)


if __name__ == "__main__":
    main()
