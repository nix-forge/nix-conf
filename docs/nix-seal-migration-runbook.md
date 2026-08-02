# nix-conf nix-seal migration runbook

This is the one-time production migration procedure. It is intentionally not
automated: the required SSH identity, administrator age identity, and approval
signing key are private operator inputs and must never enter Git, the Nix store,
arguments containing a secret value, or ordinary environment variables.

## Preconditions

- Work from a clean checkout and retain an offline backup of `secrets/`.
- Use absolute paths for the legacy SSH identity and new administrator age
  identity. The legacy key must decrypt all eight existing ciphertexts.
- Generate or select a separate approval signing key and preserve at least two
  administrator/recovery decryption paths.
- Fill `.nix-seal/public.nix` from its example using public recipients and
  artifact metadata only. Do not commit it.

## 1. Inventory and review

Run the generic age-tree adapter. It reads only ciphertext headers in dry-run
mode and writes no private material:

```console
nix run .#nix-seal -- migrate agenix \
  --repository-root . \
  --directory secrets \
  --destination .nix-seal-migration \
  --identity /absolute/path/to/legacy-ssh-key \
  --verification-identity /absolute/path/to/new-admin.agekey \
  --recipient age1new-admin... \
  --recipient age1recovery... \
  --json
```

Review the eight reported mappings. The target plan in
`flake/nix-seal-parent.nix` maps them to nine logical IDs: the old shared Nix
access-token ciphertext becomes the system secret; a second independently
encrypted ciphertext becomes the home secret. The seven Home Manager mappings
are direct filename-to-ID mappings in that file.

## 2. Create and verify staged canonical ciphertext

Repeat the preceding command with `--execute`. The adapter streams each value
directly into a side-by-side standard-age ciphertext, round-trip verifies every
output using `--verification-identity`, then atomically publishes the complete
staged tree. It does not modify `secrets/`.

Create the extra home access-token source from the legacy source, also in the
staging tree:

```console
nix run .#nix-seal -- migrate ciphertext \
  --repository-root . \
  --source secrets/IanHollow/nix-access-tokens.age \
  --destination .nix-seal-migration/IanHollow/home/ianmh/nix-access-tokens.age \
  --identity /absolute/path/to/legacy-ssh-key \
  --verification-identity /absolute/path/to/new-admin.agekey \
  --recipient age1new-admin... \
  --recipient age1recovery... \
  --execute
```

Independently reveal each staged ciphertext only to a protected stream and
compare a hash with the legacy plaintext. Retain the original tree in the
offline backup, then replace `secrets/IanHollow/` with the staged `IanHollow/`
tree using a reviewed, recoverable Git operation. The old target-encrypted files
are removed from the current tree at this cutover; Git history is not rewritten.

## 3. Provision all target artifacts

Compile the public plan, deep-check it once the staged sources have been moved
into `secrets/`, and provision every target with the signing key supplied by an
absolute path:

```console
nix eval .#nixSeal.plan --raw > /tmp/nix-conf-plan.v1.json
nix run .#nix-seal -- check --nix-plan /tmp/nix-conf-plan.v1.json --deep --repository-root .
nix run .#nix-seal -- provision --plan /tmp/nix-conf-plan.v1.json \
  --repository-root . --target host/nixos/desktop --generation 1 \
  --identity /absolute/path/to/new-admin.agekey \
  --signing-key /absolute/path/to/approval-signing-key --execute
```

Repeat provisioning for `home/ianmh/desktop`, `home/ianmh/macbook-pro-m4`, and
`host/darwin/macbook-pro-m4`. Export the resulting ciphertext-only cache or
artifact bundles and record their paths, canonical source hashes, and generation
in the ignored `.nix-seal/public.nix` file.

## 4. Activate and close out

Build and activate one low-risk Home Manager target first, then the two hosts,
then the remaining home target. Verify every listed runtime path, service reload
or restart action, and a rollback to the prior generation. Git history is not
rewritten.

If any verification fails, leave the old runtime active, restore the prior
canonical ciphertext tree, and investigate without deleting cache or runtime
generations. A compromised legacy SSH identity requires application-level secret
rotation; re-encryption alone cannot make historical ciphertext secret again.
