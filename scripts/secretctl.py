#!/usr/bin/env python3
"""SSH-recipient secret management for canonical age files."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from collections.abc import Sequence


@dataclass(frozen=True)
class SecretSpec:
    secret_id: str
    agenix_name: str
    file: Path
    consumers: tuple[str, ...]
    recipients: tuple[str, ...]


class SecretCtlError(RuntimeError):
    pass


@dataclass(frozen=True)
class IdentitySet:
    args: tuple[str, ...]
    sources: tuple[str, ...]


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _repo_root() -> Path:
    env_root = os.environ.get("SECRETCTL_REPO_ROOT")
    if env_root:
        return Path(env_root).resolve()

    cwd = Path.cwd()
    if (cwd / "flake.nix").is_file() and (cwd / "secrets").is_dir():
        return cwd

    script_root = Path(__file__).resolve().parent.parent
    if (script_root / "flake.nix").is_file() and (script_root / "secrets").is_dir():
        return script_root

    raise SecretCtlError(
        "could not determine repository root; set SECRETCTL_REPO_ROOT or run from repo root"
    )


def _run(
    command: Sequence[str], *, cwd: Path | None = None, input_bytes: bytes | None = None
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        list(command),
        cwd=str(cwd) if cwd is not None else None,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def _validate_recipient(owner: str, value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SecretCtlError(f"{owner} contains an empty recipient")
    recipient = value.strip()
    if not (recipient.startswith("ssh-ed25519 ") or recipient.startswith("ssh-rsa ")):
        raise SecretCtlError(
            f"{owner} has unsupported SSH recipient type (expected ssh-ed25519 or ssh-rsa)"
        )
    return recipient


def _validate_string_list(owner: str, field: str, value: Any) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise SecretCtlError(f"{owner} must define a list '{field}'")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise SecretCtlError(f"{owner} has an invalid '{field}' entry")
        result.append(item)
    return tuple(result)


def _normalize_public_key(value: str) -> str | None:
    parts = value.strip().split()
    if len(parts) < 2:
        return None
    key_type, key_body = parts[0], parts[1]
    if key_type not in {"ssh-ed25519", "ssh-rsa"}:
        return None
    return f"{key_type} {key_body}"


def _candidate_identity_paths(cli_identities: Sequence[str]) -> list[Path]:
    candidates: list[Path] = []

    for raw in cli_identities:
        if raw:
            candidates.append(Path(raw).expanduser())

    env_identities = os.environ.get("SECRETCTL_IDENTITIES")
    if env_identities:
        for raw in env_identities.split(os.pathsep):
            raw = raw.strip()
            if raw:
                candidates.append(Path(raw).expanduser())

    age_keys = Path.home() / ".config" / "age" / "keys.txt"
    if age_keys.is_file():
        candidates.append(age_keys)

    ssh_dir = Path.home() / ".ssh"
    if ssh_dir.is_dir():
        for public_key in sorted(ssh_dir.glob("*.pub")):
            private_key = public_key.with_suffix("")
            if private_key.is_file():
                candidates.append(private_key)

    deduped: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen or not resolved.exists():
            continue
        seen.add(resolved)
        deduped.append(resolved)
    return deduped


def _resolve_identities(spec: SecretSpec, cli_identities: Sequence[str]) -> IdentitySet:
    identity_args: list[str] = []
    sources: list[str] = []
    recipient_keys = {
        normalized
        for normalized in (
            _normalize_public_key(recipient) for recipient in spec.recipients
        )
        if normalized is not None
    }

    for candidate in _candidate_identity_paths(cli_identities):
        candidate_str = str(candidate)
        if candidate.name == "keys.txt":
            identity_args.extend(["--identity", candidate_str])
            sources.append(candidate_str)
            continue

        public_key_path = candidate.with_name(f"{candidate.name}.pub")
        if not public_key_path.is_file():
            continue

        public_key = _normalize_public_key(public_key_path.read_text(encoding="utf-8"))
        if public_key is None or public_key not in recipient_keys:
            continue

        identity_args.extend(["--identity", candidate_str])
        sources.append(candidate_str)

    if not identity_args:
        raise SecretCtlError(
            "no matching identities found for decryption; pass --identity /path/to/key, "
            "set SECRETCTL_IDENTITIES, or ensure a matching ~/.ssh/*.pub key exists"
        )

    return IdentitySet(args=tuple(identity_args), sources=tuple(sources))


def _load_index(repo_root: Path) -> dict[str, Any]:
    result = _run(["nix", "eval", "--json", ".#secretIndex"], cwd=repo_root)
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise SecretCtlError(f"failed to evaluate secret index: {stderr}")

    try:
        data = json.loads(result.stdout.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise SecretCtlError(f"invalid JSON from nix secret index: {exc}") from exc

    if not isinstance(data, dict):
        raise SecretCtlError("secret index must be a JSON object")
    return data


def _load_config(repo_root: Path) -> tuple[int, dict[str, SecretSpec]]:
    index = _load_index(repo_root)

    targets = index.get("targets")
    if not isinstance(targets, dict):
        raise SecretCtlError("secret index must define a 'targets' object")

    secrets = index.get("secrets")
    if not isinstance(secrets, dict):
        raise SecretCtlError("secret index must define a 'secrets' object")

    secrets_root = (repo_root / "secrets").resolve()
    specs: dict[str, SecretSpec] = {}
    seen_files: dict[Path, str] = {}

    for secret_id, entry in sorted(secrets.items()):
        if not isinstance(secret_id, str) or not secret_id:
            raise SecretCtlError("secret ids must be non-empty strings")
        if not isinstance(entry, dict):
            raise SecretCtlError(f"secret '{secret_id}' must be an object")
        secret_entry = cast(dict[str, Any], entry)

        agenix_name = secret_entry.get("agenixName")
        if not isinstance(agenix_name, str) or not agenix_name:
            raise SecretCtlError(f"secret '{secret_id}' must define 'agenixName'")

        file_rel = secret_entry.get("file")
        if not isinstance(file_rel, str) or not file_rel:
            raise SecretCtlError(f"secret '{secret_id}' must define 'file'")

        file_path = (repo_root / file_rel).resolve()
        try:
            file_path.relative_to(secrets_root)
        except ValueError as exc:
            raise SecretCtlError(
                f"secret '{secret_id}' file must remain under secrets/: {file_rel}"
            ) from exc

        if file_path.suffix != ".age":
            raise SecretCtlError(
                f"secret '{secret_id}' file must end with .age: {file_rel}"
            )

        consumers = _validate_string_list(
            f"secret '{secret_id}'", "consumers", secret_entry.get("consumers")
        )
        recipients = tuple(
            _validate_recipient(f"secret '{secret_id}'", recipient)
            for recipient in _validate_string_list(
                f"secret '{secret_id}'", "recipients", secret_entry.get("recipients")
            )
        )
        if file_path in seen_files:
            raise SecretCtlError(
                f"duplicate secret file mapping: {file_path} (used by {seen_files[file_path]} and {secret_id})"
            )

        specs[secret_id] = SecretSpec(
            secret_id=secret_id,
            agenix_name=agenix_name,
            file=file_path,
            consumers=consumers,
            recipients=recipients,
        )
        seen_files[file_path] = secret_id

    if not specs:
        raise SecretCtlError("secret index has no secrets")

    return len(targets), specs


def _run_age(
    *args: str,
    input_bytes: bytes | None = None,
    identity_args: Sequence[str] = (),
) -> subprocess.CompletedProcess[bytes]:
    return _run(["age", *identity_args, *args], input_bytes=input_bytes)


def _decrypt_file(path: Path, identity_args: Sequence[str]) -> bytes:
    result = _run_age("--decrypt", str(path), identity_args=identity_args)
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        if (
            "identities are required" in stderr
            or "no identity matched any of the recipients" in stderr
        ):
            raise SecretCtlError(
                f"failed to decrypt {path}: {stderr}\n"
                "hint: the local identities do not match this ciphertext's current recipients; "
                "the file is likely still encrypted to an older key set"
            )
        raise SecretCtlError(f"failed to decrypt {path}: {stderr}")
    return result.stdout


def _encrypt_bytes(
    plaintext: bytes, recipients: tuple[str, ...], out_path: Path
) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    age_args: list[str] = []
    for recipient in recipients:
        age_args.extend(["--recipient", recipient])
    result = _run_age(
        "--encrypt", *age_args, "--output", str(out_path), input_bytes=plaintext
    )
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise SecretCtlError(f"failed to encrypt {out_path}: {stderr}")


def _require_recipients(spec: SecretSpec) -> tuple[str, ...]:
    if not spec.recipients:
        raise SecretCtlError(f"secret '{spec.secret_id}' resolved to zero recipients")
    return spec.recipients


def _cmd_lint(repo_root: Path) -> int:
    target_count, specs = _load_config(repo_root)
    for spec in specs.values():
        _require_recipients(spec)
    _stdout(f"lint ok: {len(specs)} secret(s), {target_count} target(s)")
    return 0


def _lookup_secret(repo_root: Path, secret_id: str) -> SecretSpec:
    _, specs = _load_config(repo_root)
    spec = specs.get(secret_id)
    if spec is None:
        raise SecretCtlError(f"unknown secret id: {secret_id}")
    return spec


def _cmd_recipients(repo_root: Path, secret_id: str) -> int:
    spec = _lookup_secret(repo_root, secret_id)
    data = {
        "id": spec.secret_id,
        "agenix_name": spec.agenix_name,
        "file": str(spec.file.relative_to(repo_root)),
        "consumers": list(spec.consumers),
        "recipients": list(spec.recipients),
    }
    _stdout(json.dumps(data, indent=2, sort_keys=True))
    return 0


def _cmd_view(repo_root: Path, secret_id: str, cli_identities: Sequence[str]) -> int:
    spec = _lookup_secret(repo_root, secret_id)
    identities = _resolve_identities(spec, cli_identities)
    plaintext = _decrypt_file(spec.file, identities.args)
    sys.stdout.buffer.write(plaintext)
    if plaintext and not plaintext.endswith(b"\n"):
        sys.stdout.write("\n")
    return 0


def _resolve_editor() -> list[str]:
    editor = os.environ.get("VISUAL") or os.environ.get("EDITOR")
    if not editor:
        raise SecretCtlError("no editor set; define VISUAL or EDITOR")
    return shlex.split(editor)


def _cmd_edit(repo_root: Path, secret_id: str, cli_identities: Sequence[str]) -> int:
    spec = _lookup_secret(repo_root, secret_id)
    identities = _resolve_identities(spec, cli_identities)
    plaintext = _decrypt_file(spec.file, identities.args)
    editor = _resolve_editor()

    with tempfile.NamedTemporaryFile(prefix="secretctl-", delete=False) as tf:
        tmp_path = Path(tf.name)
        tf.write(plaintext)

    try:
        completed = subprocess.run([*editor, str(tmp_path)], check=False)
        if completed.returncode != 0:
            raise SecretCtlError(f"editor exited with code {completed.returncode}")
        new_plaintext = tmp_path.read_bytes()
    finally:
        tmp_path.unlink(missing_ok=True)

    _encrypt_bytes(new_plaintext, _require_recipients(spec), spec.file)
    _stdout(f"updated {spec.secret_id} -> {spec.file.relative_to(repo_root)}")
    return 0


def _cmd_encrypt(repo_root: Path, secret_id: str, source_file: Path) -> int:
    spec = _lookup_secret(repo_root, secret_id)
    try:
        plaintext = source_file.read_bytes()
    except FileNotFoundError as exc:
        raise SecretCtlError(f"plaintext file not found: {source_file}") from exc
    _encrypt_bytes(plaintext, _require_recipients(spec), spec.file)
    _stdout(f"encrypted {source_file} -> {spec.file.relative_to(repo_root)}")
    return 0


def _reencrypt_one(
    spec: SecretSpec, repo_root: Path, cli_identities: Sequence[str]
) -> None:
    if not spec.file.exists():
        raise SecretCtlError(
            f"missing ciphertext for '{spec.secret_id}': {spec.file.relative_to(repo_root)}"
        )
    identities = _resolve_identities(spec, cli_identities)
    plaintext = _decrypt_file(spec.file, identities.args)
    _encrypt_bytes(plaintext, _require_recipients(spec), spec.file)


def _cmd_reencrypt(
    repo_root: Path,
    secret_ids: list[str],
    all_secrets: bool,
    cli_identities: Sequence[str],
) -> int:
    _, specs = _load_config(repo_root)
    if all_secrets:
        selected = list(specs.values())
    else:
        if not secret_ids:
            raise SecretCtlError("provide secret ids or use --all")
        selected = []
        for secret_id in secret_ids:
            spec = specs.get(secret_id)
            if spec is None:
                raise SecretCtlError(f"unknown secret id: {secret_id}")
            selected.append(spec)

    for spec in selected:
        _reencrypt_one(spec, repo_root, cli_identities)
        _stdout(f"reencrypted {spec.secret_id}")
    return 0


def _cmd_check(repo_root: Path) -> int:
    _, specs = _load_config(repo_root)
    missing = []
    for spec in specs.values():
        _require_recipients(spec)
        if not spec.file.exists():
            missing.append(spec.file.relative_to(repo_root))

    if missing:
        joined = ", ".join(str(path) for path in missing)
        raise SecretCtlError(f"missing ciphertext file(s): {joined}")

    _stdout(f"check ok: {len(specs)} secret(s)")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-i",
        "--identity",
        action="append",
        default=[],
        help="identity file to use for decryption (repeatable)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("lint", help="validate config-driven secret index")

    recipients_parser = subparsers.add_parser(
        "recipients", help="print recipients for a secret"
    )
    recipients_parser.add_argument("secret_id")

    view_parser = subparsers.add_parser("view", help="decrypt and print a secret")
    view_parser.add_argument("secret_id")

    edit_parser = subparsers.add_parser("edit", help="edit a secret with $EDITOR")
    edit_parser.add_argument("secret_id")

    encrypt_parser = subparsers.add_parser(
        "encrypt", help="encrypt plaintext file into a secret"
    )
    encrypt_parser.add_argument("secret_id")
    encrypt_parser.add_argument("--from", dest="source_file", required=True, type=Path)

    reencrypt_parser = subparsers.add_parser(
        "reencrypt", help="re-encrypt one or more secrets"
    )
    reencrypt_parser.add_argument("secret_ids", nargs="*")
    reencrypt_parser.add_argument("--all", action="store_true")

    subparsers.add_parser("check", help="lint plus ciphertext presence checks")
    return parser


def _main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    repo_root = _repo_root()

    try:
        match args.command:
            case "lint":
                return _cmd_lint(repo_root)
            case "recipients":
                return _cmd_recipients(repo_root, args.secret_id)
            case "view":
                return _cmd_view(repo_root, args.secret_id, args.identity)
            case "edit":
                return _cmd_edit(repo_root, args.secret_id, args.identity)
            case "encrypt":
                return _cmd_encrypt(repo_root, args.secret_id, args.source_file)
            case "reencrypt":
                return _cmd_reencrypt(
                    repo_root, args.secret_ids, args.all, args.identity
                )
            case "check":
                return _cmd_check(repo_root)
            case _:
                raise SecretCtlError(f"unsupported command: {args.command}")
    except SecretCtlError as exc:
        _stderr(f"error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(_main())
