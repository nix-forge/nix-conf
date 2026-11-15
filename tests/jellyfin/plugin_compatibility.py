"""Load all configured plugins together with the selected isolated Jellyfin."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import importlib.util
import json
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING
from uuid import UUID

if TYPE_CHECKING:
    from types import ModuleType

# Identities belong to the selected upstream plugin classes, not meta.json.
IDENTITIES = {
    "Intro Skipper_nix": (
        "c83d86bb-a1e0-4c35-a113-e2101cf4ee6b",
        "Intro Skipper",
        "IntroSkipper",
    ),
    "Subtitle Extract_nix": (
        "cd893c24-b59e-4060-87b2-184070e1bf68",
        "Subtitle Extract",
        "Jellyfin.Plugin.SubtitleExtract",
    ),
    "Moonfin_nix": (
        "8c5d0e91-4f2a-4b6d-9e3f-1a7c8d9e0f2b",
        "Moonbase",
        "Moonfin.Server",
    ),
}


def load_helper(path: Path) -> ModuleType:
    """Import the maintained helper with its module identity registered.

    Returns:
        The actual maintained checker module.

    Raises:
        ValueError: The source cannot be loaded.

    """
    name = "_configured_jellyfin_intro_check"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        msg = "Cannot load maintained Intro checker"
        raise ValueError(msg)
    module = importlib.util.module_from_spec(spec)
    # Dataclasses resolve annotations through sys.modules during execution.
    previous = sys.modules.get(name)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        if previous is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = previous
        raise
    return module


def validate_plugins(helper: ModuleType, records: object, plugins: dict) -> None:
    """Require every configured upstream identity to be Active.

    Raises:
        TypeError: The API response is not a list.
        ValueError: A plugin identity, name, version or state differs.

    """
    if not isinstance(records, list):
        msg = "Plugin API must return a list"
        raise TypeError(msg)
    for key, (identifier, name, _assembly) in IDENTITIES.items():
        matches = [
            item
            for item in records
            if isinstance(item, dict)
            and helper.plugin_id(item.get("Id")) == UUID(identifier)
        ]
        if len(matches) != 1:
            msg = f"Expected one {name} plugin identity"
            raise ValueError(msg)
        actual = matches[0]
        version = actual.get("Version")
        if (
            actual.get("Name") != name
            or not isinstance(version, str)
            or helper.version_tuple(version)
            != helper.version_tuple(plugins[key]["version"])
        ):
            msg = f"Wrong {name} name/version"
            raise ValueError(msg)
        if actual.get("Status") != "Active":
            msg = f"{name} is not Active"
            raise ValueError(msg)


def validate_log(helper: ModuleType, text: str, installed: dict, plugins: dict) -> None:
    """Require exact installed DLL identities without loader or DI failures.

    Raises:
        ValueError: A required assembly is absent or plugin loading failed.

    """
    helper.validate_log(
        text, installed["Intro Skipper_nix"], plugins["Intro Skipper_nix"]["version"]
    )
    if any(
        marker in text
        for marker in (
            "Error creating Moonfin.",
            "Error creating Jellyfin.Plugin.SubtitleExtract.",
            "One or more assembly paths was invalid",
            "is not inside the plugin directory",
            "contained assembly paths that were not found",
        )
    ):
        msg = "Plugin construction or assembly directory failed"
        raise ValueError(msg)
    for key, (_identifier, _name, assembly) in IDENTITIES.items():
        signature = f"Loaded assembly {assembly}, Version={plugins[key]['version']},"
        if not any(
            signature in line
            and re.search(rf'from "?{re.escape(str(installed[key]))}"?\s*$', line)
            for line in text.splitlines()
        ):
            msg = f"Missing exact {assembly} load identity"
            raise ValueError(msg)


def _file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def install_plugins(helper: ModuleType, root: Path, plugins: dict) -> tuple[dict, int]:
    """Copy complete packages into owned disposable directories.

    Returns:
        The installed plugin DLL paths and allocated loopback port.

    Raises:
        ValueError: The selected packages or their copied contents differ.

    """
    if set(plugins) != set(IDENTITIES):
        msg = "Require the exact configured three-plugin set"
        raise ValueError(msg)
    intro = plugins["Intro Skipper_nix"]
    _dll, port = helper.prepare(
        root, Path(intro["output"]) / "IntroSkipper.dll", intro["version"]
    )
    installed = {}
    for key, (_identifier, _name, assembly) in IDENTITIES.items():
        plugin = plugins[key]
        helper.version_tuple(plugin["version"])
        source = Path(plugin["output"])
        if not source.is_absolute() or not source.is_dir():
            msg = "Plugin output is not an installed absolute directory"
            raise ValueError(msg)
        destination = root / "data/plugins" / f"{assembly}_{plugin['version']}"
        if key == "Intro Skipper_nix":
            destination = root / "data/plugins" / f"IntroSkipper_{plugin['version']}"
        # Materialize the complete package, including Moonbase's dependencies/web.
        shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=False)
        for original in source.rglob("*"):
            copied = destination / original.relative_to(source)
            if original.is_file() and _file_hash(original) != _file_hash(copied):
                msg = "Complete plugin copy changed file contents"
                raise ValueError(msg)
        for copied in [destination, *destination.rglob("*")]:
            mode = copied.stat().st_mode
            # Only new disposable inodes become writable; never package/store files.
            copied.chmod(stat.S_IMODE(mode) | (0o700 if copied.is_dir() else 0o200))
        installed[key] = destination / f"{assembly}.dll"
        if not installed[key].is_file():
            msg = "Expected plugin DLL is missing"
            raise ValueError(msg)
    return installed, port


async def _check(
    helper: ModuleType, server: str, server_version: str, plugins: dict
) -> dict:
    with tempfile.TemporaryDirectory(prefix="jellyfin-compatibility-") as temporary:
        root = Path(temporary)
        installed, port = install_plugins(helper, root, plugins)
        async with helper.launch(server, root) as running:
            try:
                await running.wait_started()
                validate_log(helper, "".join(running.lines), installed, plugins)
                api = helper.Api(port)
                await api.health()
                system = json.loads(await api.request("/System/Info/Public"))
                if helper.version_tuple(system["Version"]) != helper.version_tuple(
                    server_version
                ):
                    msg = "Running server version differs from selected package"
                    raise ValueError(msg)
                token = await api.authenticate()
                validate_plugins(
                    helper,
                    json.loads(await api.request("/Plugins", token=token)),
                    plugins,
                )
                validate_log(helper, "".join(running.lines), installed, plugins)
                if running.process.returncode is not None:
                    msg = "Server exited after compatibility validation"
                    raise RuntimeError(msg)
                return {
                    "serverVersion": system["Version"],
                    "plugins": [
                        {
                            "key": key,
                            "id": IDENTITIES[key][0],
                            "name": IDENTITIES[key][1],
                            "version": plugins[key]["version"],
                            "status": "Active",
                            "dllSHA256": _file_hash(installed[key]),
                            "output": plugins[key]["output"],
                        }
                        for key in IDENTITIES
                    ],
                }
            finally:
                if sys.exc_info()[0] is not None:
                    sys.stderr.write("".join(running.lines)[-32768:])


def main() -> None:
    """Run the isolated configured compatibility check."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--intro-checker", type=Path, required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--server-version", required=True)
    parser.add_argument("--plugins", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    result = asyncio.run(
        _check(
            load_helper(options.intro_checker),
            options.server,
            options.server_version,
            json.loads(options.plugins.read_text()),
        )
    )
    options.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
