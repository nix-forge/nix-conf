# nix-seal workflow

This repository uses the pinned `nix-seal` submodule for secret policy,
administrator-to-target rekeying, signed artifacts, and runtime activation. The
canonical ciphertext lives under shared or target-local home, host, and module directories;
target artifacts live only
in the ignored `.nix-seal/` workspace or an exported ciphertext cache.

## Public policy and local credentials

The flake-level `flake.nixSeal.administrators.ianhollow` catalog contains the
public administrator, recovery, and release identities and the default release
approval policy. nix-seal automatically selects this sole catalog for each NixOS,
nix-darwin, and Home Manager target. Target modules declare local names such
as `nixSeal.secrets."hf-token"`; nix-seal derives the canonical ID from
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

Use the intended file format before `.template`, for example
`gitconfig-username.gitconfig.template`, `jujutsu-identity.toml.template`,
and `nix-access-tokens.conf.template`. Conventional extensionless files, such as
`git-allowedsigners`, retain that name followed by `.template`. Explicit template
sources preserve existing logical names and runtime paths when source files are renamed.

Public `.template` files live with the configurations that use them:

- [Shared home templates](../homes/shared/templates/) contain Git and Jujutsu
  identity, allowed signers, and the SSH login include.
- [Shared host templates](../hosts/shared/templates/) contain the FlakeHub netrc.
- [Cross-platform templates](../modules/shared/templates/) contain one Nix-token
  template used by all four targets, with each target's own secret binding.

The small IWD profile is defined inline in
[the Wi-Fi module](../hosts/nixos/desktop/local/wifi-profile.nix). Its connection
settings and secret bindings are visible together when reading the Nix
configuration. It still renders as one protected file at activation.

[Shared home declarations](../homes/shared/nix-seal.nix) and
[shared host declarations](../hosts/shared/nix-seal.nix) own common configuration.
Each target imports the appropriate module and declares its `publicKey` and local
exceptions. Name lists replace `lib.genAttrs`; named entries carry individual
options. Declarations enable nix-seal. The framework adapter supplies the repository
root, and runtime identity paths use the platform's existing Ed25519 SSH key.
Cache paths retain their platform defaults. Templates inherit their fields' common
activation phase. These defaults preserve the evaluated target policies.
Shared directories already express reuse and do not contain an
extra `local/` directory.

The home and host `nix-seal.nix` modules declare encrypted fields and public
templates directly. nix-seal resolves same-named placeholders without a JSON
mapping. Explicit aliases and encodings remain available for application
formats that need them. Consumers use `nixSeal.templates.<name>.path` for
configurations and secret paths for raw credentials.

The completed migration's JSON inventories and authoring command are retired.
Native Nix declarations are the sole source of template bindings and policy.
Inline templates can use `${config.nixSeal.placeholder.token}` for a declared
secret named `token`; public files use `{{nix-seal:token}}`. Both forms resolve
the same binding automatically. See the standalone
[Nix authoring guide](../nix-seal/docs/nix-authoring.md) for setup and creation.
Declared missing fields appear in the separate bootstrap plan, and dependent
templates report their pending fields until ciphertext exists. Undeclared
placeholders fail evaluation.

Ciphertext storage follows the consumers' scope:

| Scope | Ciphertext directory |
| --- | --- |
| Both homes | `homes/shared/secrets/` |
| Both hosts | `hosts/shared/secrets/` |
| Systems and homes | `modules/shared/secrets/` |
| One home | `homes/<target>/local/secrets/` |
| One host | `hosts/<platform>/<target>/local/secrets/` |

The desktop-only API credential, local service settings, Wi-Fi credentials,
and host-specific system token live with their targets. Shared directories
contain files used by more than one target. Public templates follow the same
scope rules, using `templates/` as a sibling of `secrets/`.

Directory options set defaults; explicit sources handle exceptions. Home
modules select files with explicit sources when logical names differ from their
format-bearing filenames. A new declaration such as `templates = [ "app.toml" ];`
loads `templates/app.toml.template` using the default directory. No directory
is scanned to infer secrets or permissions. Sharing ciphertext does not share
runtime ownership or grant access to undeclared targets.

These are nix-conf choices. nix-seal's [storage guide](../nix-seal/docs/storage-layout.md)
documents its independent defaults and supports repositories with centralized
or colocated files. Relocating ciphertext preserves encrypted bytes and runtime
IDs but changes signed source metadata. Export fresh plans and provision target
artifacts before deploying the reorganized configuration; preserve the previous
cache generations for rollback.

Each target owns its public SSH key in `<target>/local/nix-seal/identity.pub`.
The target metadata and nix-seal declaration read that single file instead of
repeating the key. Public keys do not live under `modules/shared`.
The key in `homes/macbook-pro-m4/local/nix-seal/identity.pub` is also used for
desktop SSH authorization. The shared
allowed-signers template receives it through `publicValues.signing-key` and uses
`{{public:signing-key}}` alongside its secret email markers. Both homes retain
the same signing-key policy; their distinct target decryption keys remain distinct.

Git and
Jujutsu share private name/email values; the allowed-signers template reuses the
email fields and preserves its existing public key and `namespaces="git"`
restriction. Once migrated, Jujutsu links its identity file to a private runtime
template rather than copying values into persistent home storage.

For ordinary changes, edit the public template file or inline Nix content and
rebuild. Use nix-seal's secret creation or editing commands to change private
values. Template files contain public syntax and markers only. The generated
plan JSON is an internal interchange format; users do not maintain a template
inventory or write that plan by hand.

Use `config.nixSeal.templates.<name>.path` wherever an application needs the
rendered file. Evaluate fresh plans and provision matching signed artifacts
before deploying policy or ciphertext changes. Template and consumer changes
must be activated together. Keep existing signed caches and system generations
until rollback is no longer needed.

The service settings remain one encrypted bundle because they share a consumer
and access policy, and their variable names are private metadata. The service
reads `config.nixSeal.secrets.service-private-settings.path` directly as its
environment file. No pass-through template or duplicate rendered copy is needed.
Its `0600` permissions, services phase, and proxy restart action remain on the
secret declaration. See the
[migration review](secret-template-review.md) for historical verification and
current layout notes.

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
