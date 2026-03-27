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
SECRET_ID_MIN_PART_COUNT = 2


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


@dataclass(frozen=True)
class ResolvedSecret:
    """A looked up or index-derived secret spec."""

    spec: SecretSpec
    derived: bool


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

    recipient = value.strip()
    if not recipient.startswith(SSH_RECIPIENT_PREFIXES):
        message = f"{owner} has unsupported SSH recipient type (expected ssh-ed25519 or ssh-rsa)"
        _fail(message)

    return recipient


def _validate_string_list(owner: str, field: str, value: object) -> tuple[str, ...]:
    if not isinstance(value, list):
        message = f"{owner} must define a list '{field}'"
        _fail(message)

    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            message = f"{owner} has an invalid '{field}' entry"
            _fail(message)
        result.append(item)
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

    file_rel = secret_entry.get("file")
    if not isinstance(file_rel, str) or not file_rel:
        message = f"secret '{secret_id}' must define 'file'"
        _fail(message)

    file_path = (repo_root / file_rel).resolve()
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
        agenix_name=agenix_name,
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

    secrets = index.get("secrets")
    if not isinstance(secrets, dict):
        message = "secret index must define a 'secrets' object"
        _fail(message)

    secrets_root = (repo_root / "secrets").resolve()
    specs: dict[str, SecretSpec] = {}
    seen_files: dict[Path, str] = {}

    for secret_id, entry in sorted(secrets.items()):
        if not isinstance(secret_id, str) or not secret_id:
            message = "secret ids must be non-empty strings"
            _fail(message)

        spec = _parse_secret_spec(repo_root, secrets_root, secret_id, entry, seen_files)
        specs[secret_id] = spec
        seen_files[spec.file] = secret_id

    if not specs:
        message = "secret index has no secrets"
        _fail(message)

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
    return spec


def _secret_file_for_id(repo_root: Path, secret_id: str) -> Path:
    parts = secret_id.split(".")
    if len(parts) < SECRET_ID_MIN_PART_COUNT or any(not part for part in parts):
        message = (
            f"invalid secret id '{secret_id}' (expected '<group>.<scope...>.<name>')"
        )
        _fail(message)

    if any("/" in part or "\\" in part for part in parts):
        message = f"invalid secret id '{secret_id}' (path separators are not allowed)"
        _fail(message)

    secrets_root = (repo_root / "secrets").resolve()
    file_path = (secrets_root / Path(*parts)).with_suffix(".age").resolve()

    try:
        file_path.relative_to(secrets_root)
    except ValueError as exc:
        message = f"secret id '{secret_id}' resolves outside secrets/"
        raise SecretCtlError(message) from exc

    return file_path


def _derive_secret_from_index(  # noqa: C901, PLR0912, PLR0914, PLR0915
    repo_root: Path, secret_id: str
) -> SecretSpec:
    index = _load_index(repo_root)
    targets = index.get("targets")
    if not isinstance(targets, dict):
        message = "secret index must define a 'targets' object"
        _fail(message)

    parts = secret_id.split(".")
    if len(parts) < SECRET_ID_MIN_PART_COUNT or any(not part for part in parts):
        message = (
            f"invalid secret id '{secret_id}' (expected '<group>.<scope...>.<name>')"
        )
        _fail(message)

    group = parts[0]
    path_parts = parts[1:-1]
    agenix_name = parts[-1]

    scope = "shared"
    selector: str | None = None
    platform: str | None = None

    if path_parts:
        scope_head = path_parts[0]
        rest = path_parts[1:]

        if scope_head == "home":
            scope = "home"
            if rest:
                selector = rest[0]
        elif scope_head == "system":
            scope = "system"
            if rest:
                platform = rest[0]
                if platform not in {"nixos", "darwin"}:
                    message = (
                        f"invalid system platform in '{secret_id}': {platform} "
                        "(expected nixos or darwin)"
                    )
                    _fail(message)
            if len(rest) > 1:
                selector = rest[1]
        else:
            message = (
                f"invalid scope in '{secret_id}': {scope_head} "
                "(expected home or system for scoped secrets)"
            )
            _fail(message)

    consumers: list[str] = []
    recipient_set: set[str] = set()

    for target_id, entry in sorted(targets.items()):
        if not isinstance(target_id, str):
            message = "secret index target ids must be strings"
            _fail(message)
        if not isinstance(entry, dict):
            message = f"secret index target '{target_id}' must be an object"
            _fail(message)

        target = cast("dict[str, object]", entry)
        target_groups = _validate_string_list(
            f"target '{target_id}'", "groups", target.get("groups")
        )
        if group not in target_groups:
            continue

        target_type = target.get("type")
        if not isinstance(target_type, str):
            message = f"target '{target_id}' has an invalid 'type'"
            _fail(message)

        match = False
        if scope == "shared":
            match = True
        elif scope == "home":
            username = target.get("username")
            if username is not None and not isinstance(username, str):
                message = f"target '{target_id}' has an invalid 'username'"
                _fail(message)
            match = target_type == "home" and (selector is None or selector == username)
        elif scope == "system":
            config_name = target.get("configName")
            if config_name is not None and not isinstance(config_name, str):
                message = f"target '{target_id}' has an invalid 'configName'"
                _fail(message)
            target_platform = target.get("platform")
            if target_platform is not None and not isinstance(target_platform, str):
                message = f"target '{target_id}' has an invalid 'platform'"
                _fail(message)

            match = (
                target_type == "host"
                and (platform is None or platform == target_platform)
                and (selector is None or selector == config_name)
            )

        if not match:
            continue

        target_public_keys = _validate_string_list(
            f"target '{target_id}'", "publicKeys", target.get("publicKeys")
        )
        consumers.append(target_id)
        recipient_set.update(target_public_keys)

    if not recipient_set:
        message = (
            f"unable to derive recipients for '{secret_id}'; no matching consumer targets found"
        )
        _fail(message)

    return SecretSpec(
        secret_id=secret_id,
        agenix_name=agenix_name,
        file=_secret_file_for_id(repo_root, secret_id),
        consumers=tuple(sorted(consumers)),
        recipients=tuple(sorted(recipient_set)),
    )


def _lookup_or_derive_secret(
    repo_root: Path, secret_id: str, *, allow_derived: bool
) -> ResolvedSecret:
    try:
        return ResolvedSecret(spec=_lookup_secret(repo_root, secret_id), derived=False)
    except SecretCtlError as exc:
        if not allow_derived or str(exc) != f"unknown secret id: {secret_id}":
            raise

    return ResolvedSecret(spec=_derive_secret_from_index(repo_root, secret_id), derived=True)


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
    return shlex.split(editor)


def _cmd_edit(
    repo_root: Path,
    secret_id: str,
    cli_identities: Sequence[str],
    *,
    create: bool,
) -> int:
    if create:
        spec = _lookup_or_derive_secret(
            repo_root, secret_id, allow_derived=True
        ).spec
    else:
        spec = _lookup_secret(repo_root, secret_id)

    if spec.file.exists():
        identities = _resolve_identities(spec, cli_identities)
        plaintext = _decrypt_file(spec.file, identities.args)
        action = "updated"
    else:
        if not create:
            message = (
                f"ciphertext does not exist for '{secret_id}': {spec.file.relative_to(repo_root)}\n"
                "hint: run 'edit --create <secret-id>' to create it in your editor"
            )
            _fail(message)

        plaintext = b""
        action = "created"

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
    _stdout(f"{action} {spec.secret_id} -> {spec.file.relative_to(repo_root)}")
    return 0


def _cmd_create(repo_root: Path, secret_id: str) -> int:
    resolved = _lookup_or_derive_secret(repo_root, secret_id, allow_derived=True)
    spec = resolved.spec
    if spec.file.exists():
        message = (
            f"ciphertext already exists for '{secret_id}': {spec.file.relative_to(repo_root)}\n"
            "hint: use 'edit <secret-id>' to modify existing secrets"
        )
        _fail(message)

    editor = _resolve_editor()

    with tempfile.NamedTemporaryFile(prefix="secretctl-", delete=False) as tf:
        tmp_path = Path(tf.name)

    try:
        completed = subprocess.run([*editor, str(tmp_path)], check=False)  # noqa: S603
        if completed.returncode != 0:
            message = f"editor exited with code {completed.returncode}"
            _fail(message)

        plaintext = tmp_path.read_bytes()
        _encrypt_bytes(plaintext, _require_recipients(spec), spec.file)
    finally:
        tmp_path.unlink(missing_ok=True)

    _stdout(f"created {spec.secret_id} -> {spec.file.relative_to(repo_root)}")
    return 0


def _cmd_encrypt(repo_root: Path, secret_id: str, source_file: Path) -> int:
    resolved = _lookup_or_derive_secret(repo_root, secret_id, allow_derived=True)
    spec = resolved.spec
    try:
        plaintext = source_file.read_bytes()
    except FileNotFoundError as exc:
        message = f"plaintext file not found: {source_file}"
        raise SecretCtlError(message) from exc

    _encrypt_bytes(plaintext, _require_recipients(spec), spec.file)

    if resolved.derived:
        _stdout(
            f"created+encrypted {source_file} -> {spec.file.relative_to(repo_root)}"
        )
    else:
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
    edit_parser.add_argument(
        "--create",
        action="store_true",
        help="create the ciphertext from an empty buffer if it does not exist",
    )

    encrypt_parser = subparsers.add_parser(
        "encrypt", help="encrypt plaintext file into a secret"
    )
    encrypt_parser.add_argument("secret_id")
    encrypt_parser.add_argument("--from", dest="source_file", required=True, type=Path)

    create_parser = subparsers.add_parser(
        "create", help="create a new secret in $EDITOR"
    )
    create_parser.add_argument("secret_id")

    reencrypt_parser = subparsers.add_parser(
        "reencrypt", help="re-encrypt one or more secrets"
    )
    reencrypt_parser.add_argument("secret_ids", nargs="*")
    reencrypt_parser.add_argument("--all", action="store_true")

    subparsers.add_parser("check", help="lint plus ciphertext presence checks")
    return parser


def _dispatch_command(args: argparse.Namespace, repo_root: Path) -> int:
    command = cast("str", args.command)
    handlers = {
        "lint": lambda: _cmd_lint(repo_root),
        "recipients": lambda: _cmd_recipients(repo_root, args.secret_id),
        "view": lambda: _cmd_view(repo_root, args.secret_id, args.identity),
        "edit": lambda: _cmd_edit(
            repo_root, args.secret_id, args.identity, create=args.create
        ),
        "create": lambda: _cmd_create(repo_root, args.secret_id),
        "encrypt": lambda: _cmd_encrypt(repo_root, args.secret_id, args.source_file),
        "reencrypt": lambda: _cmd_reencrypt(
            repo_root, args.secret_ids, args.all, args.identity
        ),
        "check": lambda: _cmd_check(repo_root),
    }

    handler = handlers.get(command)
    if handler is None:
        message = f"unsupported command: {command}"
        _fail(message)

    return handler()


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
