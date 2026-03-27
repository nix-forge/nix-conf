"""SSH-recipient secret management for canonical age files."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess  # noqa: S404
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Sequence
    from typing import NoReturn


SSH_RECIPIENT_PREFIXES = ("ssh-ed25519 ", "ssh-rsa ")
PUBLIC_KEY_PART_COUNT = 2


@dataclass(frozen=True)
class SecretSpec:
    """Resolved secret metadata from the evaluated Nix index."""

    secret_id: str
    agenix_name: str
    file: Path
    consumers: tuple[str, ...]
    recipients: tuple[str, ...]


class SecretCtlError(RuntimeError):
    """Raised when secretctl cannot complete a requested operation."""


@dataclass(frozen=True)
class IdentitySet:
    """Resolved decryption identities passed through to ``age``."""

    args: tuple[str, ...]


def _fail(message: str) -> NoReturn:
    raise SecretCtlError(message)


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

    message = "could not determine repository root; set SECRETCTL_REPO_ROOT or run from repo root"
    _fail(message)


def _run(
    command: Sequence[str], *, cwd: Path | None = None, input_bytes: bytes | None = None
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(  # noqa: S603
        list(command),
        cwd=str(cwd) if cwd is not None else None,
        input=input_bytes,
        capture_output=True,
        check=False,
    )


def _validate_recipient(owner: str, value: object) -> str:
    if not isinstance(value, str) or not value.strip():
        message = f"{owner} contains an empty recipient"
        _fail(message)

    recipient = cast("str", value).strip()
    if not recipient.startswith(SSH_RECIPIENT_PREFIXES):
        message = f"{owner} has unsupported SSH recipient type (expected ssh-ed25519 or ssh-rsa)"
        _fail(message)

    return recipient


def _validate_string_list(owner: str, field: str, value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        message = f"{owner} must define a list '{field}'"
        _fail(message)

    values = cast("list[object]", value)
    result: list[str] = []
    for item in values:
        if not isinstance(item, str) or not item:
            message = f"{owner} has an invalid '{field}' entry"
            _fail(message)
        result.append(cast("str", item))
    return tuple(result)


def _normalize_public_key(value: str) -> str | None:
    parts = value.strip().split()
    if len(parts) < PUBLIC_KEY_PART_COUNT:
        return None

    key_type, key_body = parts[0], parts[1]
    if key_type not in {"ssh-ed25519", "ssh-rsa"}:
        return None

    return f"{key_type} {key_body}"


def _cli_identity_candidates(cli_identities: Sequence[str]) -> list[Path]:
    return [Path(raw).expanduser() for raw in cli_identities if raw]


def _env_identity_candidates() -> list[Path]:
    env_identities = os.environ.get("SECRETCTL_IDENTITIES")
    if not env_identities:
        return []

    raw_paths = [raw.strip() for raw in env_identities.split(os.pathsep)]
    return [Path(raw).expanduser() for raw in raw_paths if raw]


def _default_identity_candidates() -> list[Path]:
    candidates: list[Path] = []

    age_keys = Path.home() / ".config" / "age" / "keys.txt"
    if age_keys.is_file():
        candidates.append(age_keys)

    ssh_dir = Path.home() / ".ssh"
    if ssh_dir.is_dir():
        for public_key in sorted(ssh_dir.glob("*.pub")):
            private_key = public_key.with_suffix("")
            if private_key.is_file():
                candidates.append(private_key)

    return candidates


def _dedupe_existing_paths(candidates: Sequence[Path]) -> list[Path]:
    deduped: list[Path] = []
    seen: set[Path] = set()

    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in seen or not resolved.exists():
            continue
        seen.add(resolved)
        deduped.append(resolved)

    return deduped


def _candidate_identity_paths(cli_identities: Sequence[str]) -> list[Path]:
    candidates = (
        _cli_identity_candidates(cli_identities)
        + _env_identity_candidates()
        + _default_identity_candidates()
    )
    return _dedupe_existing_paths(candidates)


def _resolve_identities(spec: SecretSpec, cli_identities: Sequence[str]) -> IdentitySet:
    identity_args: list[str] = []
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
            continue

        public_key_path = candidate.with_name(f"{candidate.name}.pub")
        if not public_key_path.is_file():
            continue

        public_key = _normalize_public_key(public_key_path.read_text(encoding="utf-8"))
        if public_key is None or public_key not in recipient_keys:
            continue

        identity_args.extend(["--identity", candidate_str])

    if not identity_args:
        message = (
            "no matching identities found for decryption; pass --identity /path/to/key, "
            "set SECRETCTL_IDENTITIES, or ensure a matching ~/.ssh/*.pub key exists"
        )
        _fail(message)

    return IdentitySet(args=tuple(identity_args))


def _load_index(repo_root: Path) -> dict[str, object]:
    result = _run(["nix", "eval", "--json", ".#secretIndex"], cwd=repo_root)
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        message = f"failed to evaluate secret index: {stderr}"
        _fail(message)

    try:
        data = json.loads(result.stdout.decode("utf-8"))
    except json.JSONDecodeError as exc:
        message = f"invalid JSON from nix secret index: {exc}"
        raise SecretCtlError(message) from exc

    if not isinstance(data, dict):
        message = "secret index must be a JSON object"
        _fail(message)

    return cast("dict[str, object]", data)


def _parse_secret_spec(
    repo_root: Path,
    secrets_root: Path,
    secret_id: str,
    entry: object,
    seen_files: dict[Path, str],
) -> SecretSpec:
    if not isinstance(entry, dict):
        message = f"secret '{secret_id}' must be an object"
        _fail(message)

    secret_entry = cast("dict[str, object]", entry)

    agenix_name = secret_entry.get("agenixName")
    if not isinstance(agenix_name, str) or not agenix_name:
        message = f"secret '{secret_id}' must define 'agenixName'"
        _fail(message)
    agenix_name_str = cast("str", agenix_name)

    file_rel = secret_entry.get("file")
    if not isinstance(file_rel, str) or not file_rel:
        message = f"secret '{secret_id}' must define 'file'"
        _fail(message)
    file_rel_str = cast("str", file_rel)

    file_path = (repo_root / file_rel_str).resolve()
    try:
        file_path.relative_to(secrets_root)
    except ValueError as exc:
        message = f"secret '{secret_id}' file must remain under secrets/: {file_rel}"
        raise SecretCtlError(message) from exc

    if file_path.suffix != ".age":
        message = f"secret '{secret_id}' file must end with .age: {file_rel}"
        _fail(message)

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
        message = (
            f"duplicate secret file mapping: {file_path} "
            f"(used by {seen_files[file_path]} and {secret_id})"
        )
        _fail(message)

    return SecretSpec(
        secret_id=secret_id,
        agenix_name=agenix_name_str,
        file=file_path,
        consumers=consumers,
        recipients=recipients,
    )


def _load_config(repo_root: Path) -> tuple[int, dict[str, SecretSpec]]:
    index = _load_index(repo_root)

    targets = index.get("targets")
    if not isinstance(targets, dict):
        message = "secret index must define a 'targets' object"
        _fail(message)
    targets_dict = cast("dict[str, object]", targets)

    secrets = index.get("secrets")
    if not isinstance(secrets, dict):
        message = "secret index must define a 'secrets' object"
        _fail(message)
    secrets_dict = cast("dict[str, object]", secrets)

    secrets_root = (repo_root / "secrets").resolve()
    specs: dict[str, SecretSpec] = {}
    seen_files: dict[Path, str] = {}

    for secret_id, entry in sorted(secrets_dict.items()):
        if not isinstance(secret_id, str) or not secret_id:
            message = "secret ids must be non-empty strings"
            _fail(message)

        spec = _parse_secret_spec(repo_root, secrets_root, secret_id, entry, seen_files)
        specs[secret_id] = spec
        seen_files[spec.file] = secret_id

    if not specs:
        message = "secret index has no secrets"
        _fail(message)

    return len(targets_dict), specs


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
            message = (
                f"failed to decrypt {path}: {stderr}\n"
                "hint: the local identities do not match this ciphertext's current recipients; "
                "the file is likely still encrypted to an older key set"
            )
            _fail(message)

        message = f"failed to decrypt {path}: {stderr}"
        _fail(message)

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
        message = f"failed to encrypt {out_path}: {stderr}"
        _fail(message)


def _require_recipients(spec: SecretSpec) -> tuple[str, ...]:
    if not spec.recipients:
        message = f"secret '{spec.secret_id}' resolved to zero recipients"
        _fail(message)
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
        message = f"unknown secret id: {secret_id}"
        _fail(message)
    return cast("SecretSpec", spec)


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
    editor = os.environ.get("EDITOR") or os.environ.get("VISUAL")
    if not editor:
        message = "no editor set; define VISUAL or EDITOR"
        _fail(message)
    return shlex.split(cast("str", editor))


def _cmd_edit(repo_root: Path, secret_id: str, cli_identities: Sequence[str]) -> int:
    spec = _lookup_secret(repo_root, secret_id)
    identities = _resolve_identities(spec, cli_identities)
    plaintext = _decrypt_file(spec.file, identities.args)
    editor = _resolve_editor()

    with tempfile.NamedTemporaryFile(prefix="secretctl-", delete=False) as tf:
        tmp_path = Path(tf.name)
        tf.write(plaintext)

    try:
        completed = subprocess.run([*editor, str(tmp_path)], check=False)  # noqa: S603
        if completed.returncode != 0:
            message = f"editor exited with code {completed.returncode}"
            _fail(message)
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
        message = f"plaintext file not found: {source_file}"
        raise SecretCtlError(message) from exc

    _encrypt_bytes(plaintext, _require_recipients(spec), spec.file)
    _stdout(f"encrypted {source_file} -> {spec.file.relative_to(repo_root)}")
    return 0


def _reencrypt_one(
    spec: SecretSpec, repo_root: Path, cli_identities: Sequence[str]
) -> None:
    if not spec.file.exists():
        message = f"missing ciphertext for '{spec.secret_id}': {spec.file.relative_to(repo_root)}"
        _fail(message)

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
            message = "provide secret ids or use --all"
            _fail(message)
        selected = []
        for secret_id in secret_ids:
            spec = specs.get(secret_id)
            if spec is None:
                message = f"unknown secret id: {secret_id}"
                _fail(message)
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
        message = f"missing ciphertext file(s): {joined}"
        _fail(message)

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


def _dispatch_command(args: argparse.Namespace, repo_root: Path) -> int:
    command = cast("str", args.command)
    if command == "lint":
        result = _cmd_lint(repo_root)
    elif command == "recipients":
        result = _cmd_recipients(repo_root, cast("str", args.secret_id))
    elif command == "view":
        result = _cmd_view(
            repo_root,
            cast("str", args.secret_id),
            cast("Sequence[str]", args.identity),
        )
    elif command == "edit":
        result = _cmd_edit(
            repo_root,
            cast("str", args.secret_id),
            cast("Sequence[str]", args.identity),
        )
    elif command == "encrypt":
        result = _cmd_encrypt(
            repo_root,
            cast("str", args.secret_id),
            cast("Path", args.source_file),
        )
    elif command == "reencrypt":
        result = _cmd_reencrypt(
            repo_root,
            cast("list[str]", args.secret_ids),
            cast("bool", args.all),
            cast("Sequence[str]", args.identity),
        )
    elif command == "check":
        result = _cmd_check(repo_root)
    else:
        message = f"unsupported command: {command}"
        _fail(message)

    return result


def _main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(list(argv) if argv is not None else None)
    repo_root = _repo_root()

    try:
        return _dispatch_command(args, repo_root)
    except SecretCtlError as exc:
        _stderr(f"error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(_main())
