# nix-seal workflow

This repository uses the pinned `nix-seal` submodule for secret policy,
administrator-to-target rekeying, signed artifacts, and runtime activation. The
canonical ciphertext tree remains under `secrets/`; target artifacts live only
in the ignored `.nix-seal/` workspace or an exported ciphertext cache.

## Public policy and local credentials

`flake/nix-seal-parent.nix` is the single Nix-native source of public policy. It
defines four target IDs and nine logical secret IDs. The reused Nix access token
is intentionally split into separate system and home logical secrets, because
they have different runtime owners.

Home secrets use the target user's local group: `ianmh` on Linux and `staff` on
macOS. The target-specific policy is signed into each artifact, so activation
cannot substitute ownership metadata.

Commit `.nix-seal/public.nix` from `.nix-seal/public.nix.example`. It contains
only administrator/recovery recipients, an approval public key, and public
artifact metadata. Never place identities, signing private keys, decrypted
values, or prompt answers there.

Until that file and all signed artifacts exist, the parent nix-seal modules are
disabled. This makes an incomplete migration fail closed rather than replacing a
working runtime with an empty one.

## Operator migration

The one-time conversion requires paths to a legacy SSH identity, a new
administrator age identity, and an approval signing key. Keep all of them
outside the repository. First prepare the conversion report:

```console
nix run .#nix-seal -- migrate agenix \\
  --directory secrets \\
  --repository-root . \\
  --destination .nix-seal-migration \\
  --identity /absolute/path/to/legacy-ssh-key \\
  --verification-identity /absolute/path/to/admin.agekey \\
  --recipient age1... \\
  --dry-run
```

After reviewing the report, repeat with `--execute`. Use the generic
single-ciphertext adapter to create the additional home Nix access-token
ciphertext, then round-trip check every canonical ciphertext and provision a
signed artifact for each target. Do not delete old ciphertexts until those
checks, activation, and rollback have succeeded.

The repository-specific procedure is in `docs/nix-seal-migration-runbook.md`;
the upstream acceptance and threat-model material is in
`nix-seal/docs/adr/0006-migrations.md` and `nix-seal/THREAT_MODEL.md`.

## Daily operations

Use the pinned CLI without copying secrets into arguments or environment
variables:

```console
just secret plan
just secret recipients --plan /path/to/plan.v1.json --secret <id>
just secret rekey --plan /path/to/plan.v1.json ...
just secret reveal --plan /path/to/plan.v1.json --secret <id> --identity /absolute/key
```

`rekey` changes encryption recipients or target artifacts. `rotate` changes the
underlying application credential and must be performed as a separate, explicit
operation.
