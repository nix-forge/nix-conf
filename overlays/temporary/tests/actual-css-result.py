"""Verify selected Actual source has no theme-directory case collision."""

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import NoReturn

_PREFIX = "@actual-app/components/themes/"
_SIDEBAR = "sidebar-redesign-light.css"
_IMPORT = re.compile(
    r"\bimport\s+[A-Za-z_$][\w$]*\s+from\s+([\"'])(@actual-app/components/themes/([A-Za-z0-9_-]+\.css)\?inline)\1\s*;"
)


def _reject(message: str) -> NoReturn:
    raise ValueError(message)


def check_directory_names(names: list[str]) -> None:
    """Require an exact lowercase entry, independent of filesystem lookup case."""
    folded = [name for name in names if name.casefold() == "themes"]
    if folded != ["themes"] or any(
        name.casefold().startswith("themes~nix~case~hack~") for name in names
    ):
        _reject("The selected source has a missing or case-colliding theme directory")


def inventory(root: Path) -> dict[str, object]:
    """Verify actual source entries, CSS imports and exports without mutation.

    Returns:
        Exact source entry names, import names and content hashes.

    """
    component = root / "packages/component-library/src"
    names = sorted(entry.name for entry in component.iterdir())
    check_directory_names(names)
    directory = component / "themes"
    theme = root / "packages/desktop-client/src/style/theme.tsx"
    if (
        not directory.is_dir()
        or directory.is_symlink()
        or not theme.is_file()
        or theme.is_symlink()
    ):
        _reject("The expected source directory/module is absent or a symlink")
    content = theme.read_bytes()
    source = content.decode("utf-8")
    imports = _IMPORT.findall(source)
    if not imports or source.count(_PREFIX) != len(imports):
        _reject("Missing or ambiguous Actual inline-CSS import prefix")
    imported = [item[2] for item in imports]
    if _SIDEBAR not in imported:
        _reject(
            "The selected source does not contain the new sidebar stylesheet import"
        )
    exports = json.loads((component.parent / "package.json").read_text())["exports"]
    assets = []
    for name in imported:
        file = directory / name
        if not file.is_file() or file.is_symlink():
            _reject("An imported Actual stylesheet is missing or a symlink")
        if exports.get(f"./themes/{name}") != f"./src/themes/{name}":
            _reject("An Actual stylesheet export does not match its normal source path")
        assets.append({
            "name": name,
            "sha256": hashlib.sha256(file.read_bytes()).hexdigest(),
        })
    return {
        "caseFoldedThemeEntries": [
            name for name in names if name.casefold() == "themes"
        ],
        "themeModuleSha256": hashlib.sha256(content).hexdigest(),
        "imports": imported,
        "assets": assets,
        "sourceWasModified": False,
    }


def main() -> None:
    """Report portable source evidence for the ordinary unmodified native build."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    print(json.dumps(inventory(args.root), sort_keys=True))  # ruff: ignore[print] - Report exact source identities to CI.


if __name__ == "__main__":
    main()
