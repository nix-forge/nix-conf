# nix-seal workflow

This repository uses the pinned `nix-seal` submodule for secret policy,
administrator-to-target rekeying, signed artifacts, and runtime activation. The
canonical ciphertext lives under shared home, host, and module directories;
target artifacts live only
in the ignored `.nix-seal/` workspace or an exported ciphertext cache.

## Public policy and local credentials

The flake-level `flake.nixSeal.administrators.ianhollow` catalog contains the
public administrator, recovery, and release identities and the default release
approval policy. Each NixOS, nix-darwin, and Home Manager target selects it with
`nixSeal.administrator = "ianhollow"`. Target modules declare local names such
as `nixSeal.secrets."nix-access-tokens"`; nix-seal derives the canonical ID from
host or user metadata and default source paths from `nixSeal.secretDirectory`.
The read-only
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

Public `.template` files live with their owning home or host configuration:

- [Shared home templates](../homes/shared/local/config/secret-templates/) contain
  Git identity, allowed signers, the SSH login include, and the user Nix token
  configuration. The desktop system reuses the user token template.
- [Shared host templates](../hosts/shared/secret-templates/) contain FlakeHub
  netrc and the macOS system Nix token configuration.
- [MacBook local templates](../homes/macbook-pro-m4/local/secret-templates/)
  contain the private service environment placeholder.

Each directory's `inventory.json` maps its template files to encrypted fields.
The home and host `nix-seal.nix` configurations explicitly select these catalogs
through `inventoryFiles`. [The adapter](../lib/secrets/templates.nix) loads the
public files and selects encrypted fields for each reviewed entry. Missing fields fail
evaluation; there is no fallback to whole-file ciphertext. Consumers use
`nixSeal.templates.<name>.path` for configurations and secret paths for raw
credentials. Template files inherit the original owner, group, mode, phase,
and service actions. The inventories' `original` paths identify migration inputs
for review; activation does not read those retired files.

Ciphertext storage follows configuration ownership:

- `homes/shared/secrets/` holds private home settings and user-only credentials.
- `hosts/shared/secrets/` holds FlakeHub credentials and host-specific subfolders.
- `modules/shared/secrets/` holds the GitHub token used by homes and the desktop
  system.

Each target configures `secretDirectory` and `sharedSecretDirectory`. Individual
inventory fields use explicit `source` paths, which override directory defaults.
New scoped declarations can set `shared = true` to use the configured shared
directory. Sharing ciphertext does not share runtime ownership or grant access
to undeclared targets. nix-seal itself still defaults to the `secrets/` layout.

Git and
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

These authoring commands describe the one-time migration. The current
inventory is already migrated, so repeating them will report that there are no
unmigrated config secrets.

Run authoring as the ordinary user on the machine holding the administrator identity.
No sudo is needed when that user can read the key. The first command is a review;
the second performs the same validation and commits the encrypted fields. Values
requiring unfamiliar escaping or config syntax stop the entire migration before
writing. The service environment retains each protected value's existing
serialized quoting and omits comments. Service variable names are private
metadata too. Their assignments share one consumer and access policy, so they
are stored together in
`service-private-settings.age`. The public service template contains one
placeholder. Other configurations retain individual credential fields.

After authoring, evaluate fresh plans and provision signed artifacts for all four
targets, including unchanged raw secrets whose plan hashes also changed. Then
build and deploy using the normal host-specific workflow. Switch consumers
and runtime activation together: template paths contain a `templates/`
component that old secret paths lack. A standalone runtime switch without the
consumer changes can leave applications referencing missing files. Keep private
encrypted rollback copies and existing signed caches until both machines
activate successfully and rollback is no longer needed. A partial or interrupted
run that left field ciphertext must be reviewed before retrying; the helper
deliberately refuses to overwrite it.

See the [migration review](secret-template-review.md) for current coverage and
the [privileged-access research](secrets-privileged-access-research.md) for a
single-authentication approach if root-owned inputs are later required.

## Shared FlakeHub authentication

Both hosts reuse `hosts/shared/secrets/flakehub-login.age` and
`hosts/shared/secrets/flakehub-password.age`. The four public netrc machine
entries repeat these same two fields. Consolidation rejects differing login or
password values instead of silently discarding them.

On Linux, a root-owned login service waits for secret activation, networking,
and the Nix daemon. macOS logs in after system secret activation. Both call
`determinate-nixd auth login token --token-file` with the protected runtime
password path. Credentials are never command-line values, and Nixd maintains
its own generated netrc. The Linux login service restarts when its signed plan
changes.

Authentication does not subscribe to paid services or add FlakeHub Cache as a
configured substituter. Public flakes remain available without paid access;
FlakeHub Cache and private flakes have separate access requirements. See
[Determinate authentication](https://docs.determinate.systems/flakehub/concepts/authentication/)
and [free signup and builder access](https://docs.determinate.systems/troubleshooting/native-linux-builder/).
