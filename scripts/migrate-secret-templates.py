#!/usr/bin/env python3
"""Split this repository's config secrets without emitting their values.

Dry run by default. Subprocess errors are deliberately redacted: parsers and
decryption tools may include input excerpts in diagnostics. Plaintext stays in
process memory and pipes; only public plans and ciphertext are written to disk.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import resource
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Fixed CLI commands exchange plaintext through captured pipes.
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, TypedDict

import tomllib

if TYPE_CHECKING:
    from typing import Any

type _Plan = dict[str, Any]
type _Originals = dict[str, tuple[Path, str, _Plan]]


class _Field(TypedDict):
    source: str


class _Entry(TypedDict):
    original: str
    content: str
    fields: dict[str, _Field]
    placeholders: dict[str, str]


type _Inventory = dict[str, _Entry]

MAX_SCALAR_CHARS = 65536
FIRST_PRINTABLE = 32
ASCII_DELETE = 127
MAX_CONFIG_BYTES = 1024 * 1024
SIGNER_PARTS = 4
SUBPROCESS_TIMEOUT = 300


ROOT = Path(__file__).resolve().parent.parent
HOME_SCOPE = "ianhollow/users/ianmh"
INVENTORY_FILES = (
    "homes/shared/local/config/secret-templates/inventory.json",
    "hosts/shared/secret-templates/inventory.json",
    "homes/macbook-pro-m4/local/secret-templates/inventory.json",
)
GIT_FIELDS = {
    "gitconfig-username": ("name", "git-user-name"),
    "gitconfig-useremail": ("email", "git-user-email"),
    "gitconfig-useremail-cornell": ("email", "git-user-email-cornell"),
    "gitconfig-useremail-github": ("email", "git-user-email-github"),
}
CONFIG_NAMES = set(GIT_FIELDS) | {
    "nix-access-tokens",
    "cornell-net-id-ssh-config",
    "git-allowedsigners",
    "flakehub-netrc",
    "service-runtime-environment",
}
TARGETS = [
    "nixosConfigurations.desktop.config.nixSeal",
    "nixosConfigurations.desktop.config.home-manager.users.ianmh.nixSeal",
    "darwinConfigurations.macbook-pro-m4.config.nixSeal",
    "darwinConfigurations.macbook-pro-m4.config.home-manager.users.ianmh.nixSeal",
]


class MigrationError(Exception):
    """An error whose message contains no private input."""


def _require(condition: object, message: str) -> None:
    if not condition:
        raise MigrationError(message)


def _checked_match(match: re.Match[str] | None, message: str) -> re.Match[str]:
    if match is None:
        raise MigrationError(message)
    return match


def _run(argv: list[str], data: bytes | None = None) -> bytes:
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Fixed commands; no shell.
        argv, input=data, capture_output=True, check=False, timeout=SUBPROCESS_TIMEOUT
    )
    _require(
        result.returncode == 0,
        "Subprocess failed; diagnostic suppressed to protect values.",
    )
    return result.stdout


def _scalar(value: str) -> str:
    _require(
        bool(value) and len(value) <= MAX_SCALAR_CHARS, "Empty or oversized scalar."
    )
    _require(
        not any((ord(c) < FIRST_PRINTABLE or ord(c) == ASCII_DELETE) for c in value),
        "Control character in scalar.",
    )
    _require("{{nix-seal:" not in value, "Reserved template marker in scalar.")
    return value


def _word(value: str) -> str:
    _require(
        re.fullmatch(r"[A-Za-z0-9_.@+%:/=-]+", value) is not None,
        "Unsupported scalar syntax.",
    )
    return _scalar(value)


def _entry(source: str, content: str, values: dict[str, str]) -> _Entry:
    scope = source.removeprefix("secrets/").rsplit("/", 1)[0]
    field_root = (
        f"secrets/{scope.split('/', 1)[0]}/shared"
        if Path(source).stem == "flakehub-netrc"
        else f"secrets/{scope}/fields"
    )
    return {
        "original": source,
        "content": content,
        "fields": {name: {"source": f"{field_root}/{name}.age"} for name in values},
        "placeholders": {name: name for name in values},
    }


def _marker(name: str) -> str:
    return "{{nix-seal:" + name + "}}"


def _parse_git(name: str, text: str) -> tuple[str, dict[str, str]]:
    values: dict[str, str] = {}
    key, field = GIT_FIELDS[name]
    match = _checked_match(
        re.fullmatch(r"\s*\[user\]\s+" + key + r"\s*=\s*([^\n\r]+)\s*", text),
        "Unexpected Git config structure.",
    )
    value = _scalar(match[1].strip())
    # One scalar can be safely reused in Git, TOML, and allowed_signers.
    _require(
        not any(c in value for c in '"\\#;'),
        "Git value needs explicit escaping review.",
    )
    if key == "email":
        _word(value)
    values[field] = value
    content = f'[user]\n    {key} = "{_marker(field)}"\n'
    return content, values


def _parse_ssh(text: str) -> tuple[str, dict[str, str]]:
    values: dict[str, str] = {}
    match = _checked_match(
        re.fullmatch(r"\s*User\s+(\S+)\s*", text), "Unexpected SSH include structure."
    )
    values["cornell-net-id"] = _word(match[1])
    content = "User " + _marker("cornell-net-id") + "\n"
    return content, values


def _parse_tokens(text: str) -> tuple[str, dict[str, str]]:
    values: dict[str, str] = {}
    match = _checked_match(
        re.fullmatch(r"\s*access-tokens\s*=\s*([^\n\r]+)\s*", text),
        "Unexpected Nix token config structure.",
    )
    tokens = []
    for item in match[1].split():
        host, token = item.split("=", 1)
        _require(
            host in {"github.com", "gitlab.com", "github.coecis.cornell.edu"},
            "Nix token host needs public metadata review.",
        )
        field = "nix-token-" + host.replace(".", "-")
        _require(field not in values, "Duplicate Nix token host.")
        values[field] = _word(token)
        tokens.append(host + "=" + _marker(field))
    content = "access-tokens = " + " ".join(tokens) + "\n"
    return content, values


def _parse_signers(
    text: str, home_values: dict[str, str], public_key: str
) -> tuple[str, dict[str, str]]:
    values: dict[str, str] = {}
    lines = []
    emails = {
        key: val for key, val in home_values.items() if key.startswith("git-user-email")
    }
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split()
        _require(
            len(parts) == SIGNER_PARTS
            and parts[1] == 'namespaces="git"'
            and " ".join(parts[2:]) == public_key,
            "Allowed signer key/options need public metadata review.",
        )
        matches = [key for key, val in emails.items() if val == parts[0]]
        _require(
            len(matches) == 1,
            "Allowed signer principal does not uniquely match a protected email.",
        )
        field = matches[0]
        values[field] = emails[field]
        lines.append(_marker(field) + ' namespaces="git" ' + public_key)
    _require(bool(lines), "Empty allowed-signers file.")
    content = "\n".join(lines) + "\n"
    return content, values


def _parse_netrc(text: str) -> tuple[str, dict[str, str]]:
    values: dict[str, str] = {}
    tokens = text.split()
    _require(len(tokens) % 6 == 0 and bool(tokens), "Unsupported netrc structure.")
    lines = []
    seen: set[str] = set()
    for offset in range(0, len(tokens), 6):
        machine, host, login, user, password, token = tokens[offset : offset + 6]
        _require(
            (machine, login, password) == ("machine", "login", "password"),
            "Unsupported netrc entry.",
        )
        _require(
            host
            in {
                "flakehub.com",
                "api.flakehub.com",
                "cache.flakehub.com",
                "edge.cache.flakehub.com",
            },
            "Netrc host needs public metadata review.",
        )
        _require(host not in seen, "Duplicate netrc host.")
        seen.add(host)
        credentials = {"flakehub-login": _word(user), "flakehub-password": _word(token)}
        _require(
            not values or values == credentials,
            "FlakeHub entries do not share one login and password.",
        )
        values = credentials
        lines.append(
            f"machine {host} login {_marker('flakehub-login')} password {_marker('flakehub-password')}"
        )
    content = "\n".join(lines) + "\n"
    return content, values


def _parse_environment(text: str) -> tuple[str, dict[str, str]]:
    lines = []
    seen: set[str] = set()
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _checked_match(
            re.fullmatch(r"([A-Z_][A-Z_0-9]*)=(.*)", line),
            "Environment syntax needs review.",
        )
        key = match[1]
        _require(key not in seen, "Duplicate environment key.")
        seen.add(key)
        lines.append(_scalar(line))
    _require(bool(lines), "Empty service environment.")
    # These assignments share one consumer and access policy. Keep their private
    # names and values together instead of creating a ciphertext per setting.
    field = "service-private-settings"
    return _marker(field), {field: "\n".join(lines) + "\n"}


def _split_config(
    source: str, data: bytes, home_values: dict[str, str], public_key: str
) -> tuple[_Entry, dict[str, str]]:
    _require(len(data) <= MAX_CONFIG_BYTES, "Config exceeds migration bound.")
    name = Path(source).stem
    text = data.decode("utf-8")
    if name in GIT_FIELDS:
        content, values = _parse_git(name, text)
    elif name == "git-allowedsigners":
        content, values = _parse_signers(text, home_values, public_key)
    else:
        parsers = {
            "cornell-net-id-ssh-config": _parse_ssh,
            "nix-access-tokens": _parse_tokens,
            "flakehub-netrc": _parse_netrc,
            "service-runtime-environment": _parse_environment,
        }
        parser = parsers.get(name)
        _require(parser is not None, "Unsupported config type.")
        if parser is None:
            raise AssertionError
        content, values = parser(text)
    return _entry(source, content, values), values


def _render_template(spec: _Entry, values: dict[str, str]) -> str:
    placeholders = spec["placeholders"]
    _require(
        set(placeholders.values()) == set(values),
        "Template field mapping differs from extracted fields.",
    )
    used: set[str] = set()

    def substitute(match: re.Match[str]) -> str:
        name = match[1]
        _require(name in placeholders, "Template contains an undeclared placeholder.")
        used.add(name)
        return values[placeholders[name]]

    rendered = re.sub(r"\{\{nix-seal:([^{}]+)\}\}", substitute, spec["content"])
    _require(
        used == set(placeholders),
        "Template contains an unused placeholder declaration.",
    )
    _require("{{nix-seal:" not in rendered, "Template contains an unresolved marker.")
    return rendered


def _semantic_config(name: str, text: str) -> bytes | list[str] | list[list[str]]:
    if name in GIT_FIELDS:
        # Compare Git's actual parser results, including quoting and whitespace.
        # Both configurations stay in a pipe and diagnostics remain redacted.
        return _run(
            ["git", "config", "--file", "/dev/stdin", "--null", "--list"], text.encode()
        )
    if name == "service-runtime-environment":
        # Preserve value quoting verbatim; never execute shell or expand variables.
        return [
            line
            for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    if name == "nix-access-tokens":
        key, value = text.split("=", 1)
        return [key.strip(), *value.split()]
    if name in {"cornell-net-id-ssh-config", "flakehub-netrc"}:
        return text.split()
    if name == "git-allowedsigners":
        return [line.split() for line in text.splitlines() if line.strip()]
    _require(False, "Unsupported configuration comparison.")
    raise AssertionError


def _verify_template(
    source: str, original: bytes, spec: _Entry, values: dict[str, str]
) -> None:
    _require(
        spec["original"] == source,
        "Template original source differs from reviewed input.",
    )
    rendered = _render_template(spec, values)
    name = Path(source).stem
    _require(
        _semantic_config(name, original.decode("utf-8"))
        == _semantic_config(name, rendered),
        "Rendered configuration differs from the original.",
    )
    if name in GIT_FIELDS:
        key, field = GIT_FIELDS[name]
        identity = tomllib.loads(f'[user]\n{key} = "{values[field]}"\n')
        _require(
            identity == {"user": {key: values[field]}},
            "Jujutsu identity does not preserve the Git scalar.",
        )


def _public_macbook_key() -> str:
    text = (ROOT / "homes/macbook-pro-m4/nix-seal.nix").read_text()
    match = _checked_match(
        re.search(r"ssh-ed25519 [A-Za-z0-9+/=]+", text), "Public MacBook key missing."
    )
    return match[0]


def _retain_field_sources(spec: _Entry, inventory: _Inventory) -> None:
    existing = inventory.get(spec["original"])
    if existing is not None:
        _require(
            existing["fields"].keys() == spec["fields"].keys(),
            "Reviewed template fields differ.",
        )
        spec["fields"] = existing["fields"]


def _inspect_runtime(directory: Path) -> _Inventory:
    existing = _read_inventory()
    inventory, home_values = {}, {}
    for name in [
        *GIT_FIELDS,
        "cornell-net-id-ssh-config",
        "nix-access-tokens",
        "git-allowedsigners",
    ]:
        source = f"secrets/{HOME_SCOPE}/{name}.age"
        data = (directory / name).read_bytes()
        spec, values = _split_config(source, data, home_values, _public_macbook_key())
        _retain_field_sources(spec, existing)
        _verify_template(source, data, spec, values)
        inventory[source] = spec
        home_values.update(values)
    return inventory


def _collect_plans(workspace: Path) -> tuple[_Plan, _Originals]:
    originals: _Originals = {}
    # These plans contain public metadata only. Give each target identity a
    # unique name before combining policies for the create-only batch.
    combined: _Plan | None = None
    for index, target in enumerate(TARGETS):
        plan = json.loads(
            _run([
                "nix",
                "eval",
                "--raw",
                f"path:{ROOT}#{target}.planFile",
                "--apply",
                "x: x.text",
            ])
        )
        plan_path = workspace / f"original-{index}.json"
        plan_path.write_text(json.dumps(plan))
        for secret_id, policy in plan["secrets"].items():
            source = policy["source"]
            if Path(source).stem in CONFIG_NAMES:
                originals.setdefault(source, (plan_path, secret_id, policy))
        target_key = f"migration-target-{index}"
        plan["identities"][target_key] = plan["identities"].pop("target")
        for target_policy in plan["targets"].values():
            target_policy["identity"] = target_key
        if combined is None:
            combined = copy.deepcopy(plan)
            combined["secrets"] = {}
            combined["templates"] = {}
        else:
            combined["identities"].update(plan["identities"])
            combined["targets"].update(plan["targets"])
    if combined is None:
        message = "No target plans."
        raise MigrationError(message)
    return combined, originals


def _extract_fields(
    originals: _Originals, identity: Path, inventory: _Inventory
) -> tuple[dict[str, str], dict[str, _Plan]]:
    private_values: dict[str, str] = {}
    home_values: dict[str, str] = {}
    declarations: dict[str, _Plan] = {}
    # Extract identity values before constructing the allowed-signers template.
    order = sorted(
        originals,
        key=lambda source: (Path(source).stem == "git-allowedsigners", source),
    )
    for source in order:
        plan_path, old_id, policy = originals[source]
        data = _run([
            "nix-seal",
            "secret",
            "reveal",
            "--plan",
            str(plan_path),
            "--repository-root",
            str(ROOT),
            "--secret",
            old_id,
            "--identity",
            str(identity),
        ])
        spec, values = _split_config(source, data, home_values, _public_macbook_key())
        _retain_field_sources(spec, inventory)
        _verify_template(source, data, spec, values)
        inventory[source] = spec
        if source.startswith(f"secrets/{HOME_SCOPE}/"):
            home_values.update(values)
        for name, value in values.items():
            field_source = spec["fields"][name]["source"]
            field_id = field_source.removeprefix("secrets/").removesuffix(".age")
            _require(
                field_id not in private_values or private_values[field_id] == value,
                "Conflicting shared field values.",
            )
            private_values[field_id] = value
            declaration = copy.deepcopy(policy)
            declaration["source"] = field_source
            # This temporary plan is exclusively an authoring input. A real Nix
            # evaluation hashes the new ciphertext before any provisioning.
            declaration["sourceCiphertextHash"] = "0" * 64
            declarations[field_id] = declaration
    _require(bool(private_values), "No unmigrated config secrets found.")
    return private_values, declarations


def _prepare_batch(
    private_values: dict[str, str], declarations: dict[str, _Plan]
) -> tuple[_Plan, dict[str, str]]:
    mapping = {"schema": "nix-seal.collection.v1", "entries": []}
    collection = {}
    for index, (field_id, value) in enumerate(private_values.items()):
        key = f"field{index}"
        collection[key] = value
        mapping["entries"].append({"secret": field_id, "path": key})
        _require(
            not (ROOT / declarations[field_id]["source"]).exists(),
            "Field already exists; review partial migration before retrying.",
        )
    return mapping, collection


def _author_fields(
    combined: _Plan, private_values: dict[str, str], identity: Path, workspace: Path
) -> None:
    mapping, collection = _prepare_batch(private_values, combined["secrets"])
    plan_path, mapping_path = workspace / "authoring.json", workspace / "mapping.json"
    plan_path.write_text(json.dumps(combined))
    mapping_path.write_text(json.dumps(mapping))
    _run(
        [
            "nix-seal",
            "secret",
            "batch",
            "--plan",
            str(plan_path),
            "--repository-root",
            str(ROOT),
            "--identity",
            str(identity),
            "--mapping",
            str(mapping_path),
            "--format",
            "json",
        ],
        json.dumps(collection).encode(),
    )
    # Verify every newly encrypted scalar through the authorized identity.
    for field_id in private_values:
        combined["secrets"][field_id]["sourceCiphertextHash"] = hashlib.sha256(
            (ROOT / combined["secrets"][field_id]["source"]).read_bytes()
        ).hexdigest()
    plan_path.write_text(json.dumps(combined))
    for field_id, value in private_values.items():
        actual = _run([
            "nix-seal",
            "secret",
            "reveal",
            "--plan",
            str(plan_path),
            "--repository-root",
            str(ROOT),
            "--secret",
            field_id,
            "--identity",
            str(identity),
        ])
        _require(actual == value.encode(), "Encrypted field round-trip failed.")


def _migrate(identity: Path, execute: bool, workspace: Path) -> None:
    inventory = _read_inventory()
    combined, originals = _collect_plans(workspace)
    private_values, declarations = _extract_fields(originals, identity, inventory)
    combined["secrets"] = declarations
    # Apply preconditions during dry-run too, without creating any ciphertext.
    _prepare_batch(private_values, declarations)
    sys.stdout.write(
        f"Reviewed {len(originals)} config sources; {len(private_values)} protected fields. Templates verified; no values displayed.\n"
    )
    if execute:
        _author_fields(combined, private_values, identity, workspace)
        _write_inventory(inventory)
        sys.stdout.write(
            "Field ciphertexts verified and public inventory updated. Provision all four target plans before activation. Originals retained.\n"
        )


def _read_inventory() -> _Inventory:
    inventory: _Inventory = {}
    for relative in INVENTORY_FILES:
        catalog = ROOT / relative
        for source, entry in json.loads(catalog.read_text()).items():
            _require(source not in inventory, "Duplicate template inventory source.")
            template = catalog.parent / entry.pop("template")
            entry["content"] = template.read_text()
            inventory[source] = entry
    return inventory


def _write_inventory(inventory: _Inventory) -> None:
    # Keep public syntax beside its owning configuration. Existing catalogs
    # decide placement; authoring must not invent or silently omit an owner.
    _require(
        inventory.keys() == _read_inventory().keys(),
        "Assign new templates to a home or host inventory before authoring.",
    )
    for relative in INVENTORY_FILES:
        destination = ROOT / relative
        entries = json.loads(destination.read_text())
        for source, previous in entries.items():
            spec = inventory[source]
            template = destination.parent / previous["template"]
            temporary = template.with_suffix(".template.tmp")
            with temporary.open("x") as output:
                output.write(spec["content"])
            temporary.replace(template)
            entries[source] = {
                key: value for key, value in spec.items() if key != "content"
            } | {"template": previous["template"]}
        temporary = destination.with_suffix(".json.tmp")
        with temporary.open("x") as output:
            output.write(json.dumps(entries, indent=2, sort_keys=True) + "\n")
        temporary.replace(destination)


def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--inspect-runtime-home", type=Path)
    parser.add_argument("--write-public-inventory", action="store_true")
    args = parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o077)
    if args.inspect_runtime_home:
        _require(
            not args.execute and args.identity is None,
            "Runtime review cannot author ciphertext.",
        )
        inventory = _inspect_runtime(args.inspect_runtime_home)
        if args.write_public_inventory:
            existing = _read_inventory()
            _write_inventory(existing | inventory)
        sys.stdout.write(
            f"Reviewed {len(inventory)} home config templates. Private values were not written or displayed.\n"
        )
        return
    _require(
        args.identity is not None,
        "Provide an administrator identity path, not key contents.",
    )
    _require(
        not args.write_public_inventory,
        "Use --execute to publish a canonical migration inventory.",
    )
    _require(
        not args.identity.resolve().is_relative_to(ROOT)
        and not args.identity.resolve().is_relative_to("/nix/store"),
        "Identity must be outside the repository and Nix store.",
    )
    with tempfile.TemporaryDirectory(
        prefix="nix-seal-template-migration-"
    ) as temporary:
        _migrate(args.identity.resolve(), args.execute, Path(temporary))


if __name__ == "__main__":
    try:
        _main()
    except MigrationError as error:
        sys.stderr.write(str(error) + "\n")
        sys.exit(1)
    except Exception:  # ruff: ignore[blind-except] - Even unexpected parser exceptions must not expose private input.
        sys.stderr.write(
            "Migration failed; diagnostic suppressed to protect private input. No activation attempted.\n"
        )
        sys.exit(1)
