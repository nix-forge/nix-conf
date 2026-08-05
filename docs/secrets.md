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

Home secrets use the target user's local group: `ianmh` on Linux and `staff` on
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
