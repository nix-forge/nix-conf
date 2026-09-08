# nix-seal workflow

This repository uses the pinned `nix-seal` submodule for secret policy,
administrator-to-target rekeying, signed artifacts, and runtime activation. The
canonical ciphertext tree remains under `secrets/`; target artifacts live only
in the ignored `.nix-seal/` workspace or an exported ciphertext cache.

## Public policy and local credentials

The flake-level `flake.nixSeal.administrators.ianhollow` catalog contains the
public administrator, recovery, and release identities and the default release
approval policy. Each NixOS, nix-darwin, and Home Manager target selects it with
`nixSeal.administrator = "ianhollow"`. Target modules declare local names such
as `nixSeal.secrets."nix-access-tokens"`; nix-seal derives the canonical ID and
administrator-scoped source from the host or user metadata. The read-only
`config.nixSeal.secrets.<local-name>.id` is available when a CLI or rekey
workflow needs the canonical ID, while application modules continue to use the
local-name `.path`.

The reused Nix access token is intentionally split into separate system and home
logical secrets because they have different runtime owners. Framework metadata
derives host and user scopes; `nixSeal.targetId` and `nixSeal.secretScope`
remain explicit override escape hatches. The
`nix-seal.flakeModules.nix-config-framework` adapter passes the flake catalog
through `nixConfigFramework.extraSpecialArgs`.

Home secrets use the target user's local group: `user` on Linux and `staff` on
macOS. The target-specific policy is signed into each artifact, so activation
cannot substitute ownership metadata.

There is no deployment lock file or artifact flake input. `plan.v2` pins each
canonical ciphertext's SHA-256 hash. Activation discovers and verifies the
matching signed artifact from the local cache, failing closed if it is missing,
stale, unsigned, or ambiguous. Never place identities, signing private keys,
decrypted values, or prompt answers in the repository.

## Daily operations

Use the pinned CLI without copying secrets into arguments or environment
variables:

```console
just secret recipients --plan /path/to/plan.v2.json --secret <id>
just secret rekey --plan /path/to/plan.v2.json ...
just secret reveal --plan /path/to/plan.v2.json --secret <id> --identity /absolute/key
```

`rekey` changes encryption recipients or target artifacts. `rotate` changes the
underlying application credential and must be performed as a separate, explicit
operation.

## Config templates

The public [template inventory](../secrets/templates.json) holds configuration
syntax and explicit field references. [The adapter](../secrets/templates.nix)
replaces a legacy whole-file declaration only when every field ciphertext for
that entry exists. Consumers prefer `nixSeal.templates.<name>.path`, falling back
to the existing secret while migration is pending. Template files inherit the
original owner, group, mode, phase, and service actions.

New ciphertext goes under each original scope's `fields/` directory. Git and
Jujutsu share private name/email values; the allowed-signers template reuses the
email fields and preserves its existing public key and `namespaces="git"`
restriction. Once migrated, Jujutsu links its identity file to a private runtime
template rather than copying values into persistent home storage.

The authoring command reads canonical ciphertext through an authorized identity,
validates the known application syntax, and sends extracted fields to one
create-only `nix-seal secret batch` transaction. It does not print values, create
plaintext temporary files, overwrite existing field ciphertext, or activate a
configuration. Parser diagnostics are suppressed because they can contain input.
Its temporary plans contain only public metadata; their zero source hashes are
authoring placeholders and must never be used for provisioning or activation.

```console
just secret-template-migrate --identity /absolute/administrator-identity
just secret-template-migrate --identity /absolute/administrator-identity --execute
```

Run this as the ordinary user on the machine holding the administrator identity.
No sudo is needed when that user can read the key. The first command is a review;
the second performs the same validation and commits the encrypted fields. Values
requiring unfamiliar escaping or config syntax stop the entire migration before
writing. The service environment retains each value's existing serialized
quoting, and omits comments from the public template.

After authoring, evaluate fresh plans and provision signed artifacts for all four
targets, including unchanged raw secrets whose plan hashes also changed. Then
build and deploy using the normal host-specific workflow. Keep original
ciphertext until both machines activate successfully and rollback is no longer
needed. A partial or interrupted run that left field ciphertext must be reviewed
before retrying; the helper deliberately refuses to overwrite it.

See the [migration review](secret-template-review.md) for current coverage and
the [privileged-access research](secrets-privileged-access-research.md) for a
single-authentication approach if root-owned inputs are later required.
