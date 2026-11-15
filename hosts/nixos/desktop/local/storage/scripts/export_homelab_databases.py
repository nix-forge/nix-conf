"""Create consistent private database exports without stopping application writers."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any


class ExportError(ValueError):
    """A required database could not produce a complete export."""


def fingerprint(path: Path) -> dict[str, Any]:
    """Describe one private export without including its contents.

    Returns:
        Size and SHA-256 of the completed file.

    """
    path.chmod(0o600)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"file": path.name, "bytes": path.stat().st_size, "sha256": digest}


def sqlite_export(entry: dict[str, Any], directory: Path) -> dict[str, Any]:
    """Capture committed WAL records using SQLite's online backup API.

    Returns:
        Completed-copy evidence or an explicit absent optional database.

    Raises:
        ExportError: A required source is absent or the copy fails validation.

    """
    source = Path(entry["path"]).resolve()
    if not source.is_file():
        if entry.get("optional"):
            return {"name": entry["name"], "kind": "sqlite", "absent": True}
        message = f"Required database is absent: {entry['name']}"
        raise ExportError(message)
    target = directory / (entry["name"] + ".sqlite")
    with (
        sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=30) as live,
        sqlite3.connect(target) as copy,
    ):
        live.backup(copy, pages=128)
        result = copy.execute("PRAGMA quick_check").fetchall()
        if result != [("ok",)]:
            message = f"SQLite copy failed validation: {entry['name']}"
            raise ExportError(message)
    return {"name": entry["name"], "kind": "sqlite", **fingerprint(target)}


def postgres_exports(cluster: dict[str, Any], directory: Path) -> list[dict[str, Any]]:
    """Export all connectable application databases with their matching PG tools.

    Returns:
        Custom-format database dumps and the private cluster roles export.

    Raises:
        ExportError: Discovery returned an unsafe database name.

    """

    def command(tool: str, *arguments: str) -> list[str]:
        return [
            *cluster["commandPrefix"],
            str(Path(cluster["package"]) / "bin" / tool),
            "--host=" + cluster["socket"],
            "--username=" + cluster["user"],
            *arguments,
        ]

    query = (
        "SELECT coalesce(json_agg(datname ORDER BY datname), '[]')::text "
        "FROM pg_database WHERE datallowconn AND NOT datistemplate"
    )
    response = subprocess.run(
        command(
            "psql",
            "-XAt",
            "--set=ON_ERROR_STOP=1",
            "--dbname=postgres",
            "--command=" + query,
        ),
        check=True,
        capture_output=True,
        text=True,
        shell=False,
    )
    databases = json.loads(response.stdout)
    if not isinstance(databases, list) or not all(
        isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_-]+", name)
        for name in databases
    ):
        raise ExportError("PostgreSQL discovery returned an unsafe database name")
    records = []
    exports = [("globals", "pg_dumpall", ["--globals-only"], ".sql")]
    exports.extend(
        (name, "pg_dump", ["--format=custom", "--dbname=" + name], ".dump")
        for name in databases
    )
    for name, tool, arguments, suffix in exports:
        path = directory / (cluster["name"] + "-" + name + suffix)
        with path.open("xb") as stream:
            subprocess.run(
                command(tool, *arguments),
                stdout=stream,
                stderr=subprocess.PIPE,
                check=True,
                shell=False,
            )
        records.append({
            "name": name,
            "cluster": cluster["name"],
            "kind": "postgresql",
            **fingerprint(path),
        })
    return records


def export(policy: dict[str, Any]) -> dict[str, Any]:
    """Publish a complete generation, preserving the previous one on any failure.

    Returns:
        The completed generation's manifest.

    """
    root = Path(policy["directory"])
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    records = []
    with tempfile.TemporaryDirectory(prefix="pending-", dir=root) as temporary:
        staging = Path(temporary)
        records.extend(sqlite_export(entry, staging) for entry in policy["sqlite"])
        for cluster in policy["postgresql"]:
            records.extend(postgres_exports(cluster, staging))
        manifest = {
            "format": "homelab-database-backup/v1",
            "createdNs": time.time_ns(),
            "databases": records,
        }
        (staging / "manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        (staging / "manifest.json").chmod(0o600)
        generation = root / ("generation-" + str(manifest["createdNs"]))
        staging.rename(generation)
    # TemporaryDirectory tolerates its now-renamed source. Restic includes the
    # real generation directories, rather than backing up only a symlink.
    with tempfile.NamedTemporaryFile(
        encoding="utf-8", mode="w", prefix=".latest-", dir=root, delete=False
    ) as stream:
        json.dump(
            {"generation": generation.name, "createdNs": manifest["createdNs"]}, stream
        )
        stream.write("\n")
        marker = Path(stream.name)
    marker.replace(root / "latest.json")
    generations = sorted(root.glob("generation-*"), key=lambda path: path.name)
    for previous in generations[:-2]:
        metadata = previous / "manifest.json"
        if (
            previous.is_dir()
            and metadata.is_file()
            and json.loads(metadata.read_text())["format"]
            == "homelab-database-backup/v1"
        ):
            shutil.rmtree(previous)
    return manifest


def main() -> None:
    """Run the host-owned export under its service deadline and private umask."""
    os.umask(0o077)
    policy = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    manifest = export(policy)
    print(f"Published consistent database exports: {len(manifest['databases'])}")


if __name__ == "__main__":
    main()
