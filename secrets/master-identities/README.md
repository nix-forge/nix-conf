# Master Identity Setup

This repository uses a single-owner master identity model.

Committed key material:

- `secrets/master-identities/main.pub` (public key only)

Local private key material (never committed):

- `~/.config/agenix/master.agekey`

## Key Model

- `main.pub` is the public recipient (`age1...`) and is safe to commit.
- `master.agekey` is the private identity and must stay outside git.
- `age` always uses a keypair. The public key is derived from the private key.

## Standard Setup

This repo now uses one local key format and one path:

- `~/.config/agenix/master.agekey`

Security baseline:

- `chmod 700 ~/.config/agenix`
- `chmod 600 ~/.config/agenix/master.agekey`
- full-disk encryption enabled

## Create/Rotate Master Identity

Create or rotate:

```bash
just master-key-create
```

Force rotate existing identity:

```bash
FORCE=true just master-key-create
```

After creating/rotating:

```bash
just rekey-update-masterkeys
just rekey
```

## Configuration Expectations

Set `masterIdentityPath` to an absolute string path outside `/nix/store`:

- `"/Users/<user>/.config/agenix/master.agekey"` on macOS
- `"/home/<user>/.config/agenix/master.agekey"` on Linux

For standalone Home Manager, `masterIdentityPath` is optional. Set it only on
configs that manage/rekey secrets.

For Home Manager under NixOS/darwin, the system-level value is authoritative.

## Live ISO Install Notes

Installing NixOS from a live ISO does not require your personal master identity
on the installer environment to boot the system.

What is required for deployed secret decryption is the target host SSH keypair
(and secrets rekeyed for that host key).

If you also need to run rekey/edit operations from that machine later, then copy
`master.agekey` from secure backup media after install and set permissions.

## Cleanup Old `master.age`

This repo now standardizes on `master.agekey`. If you still have an old
`~/.config/agenix/master.age`, remove it after confirming `master.agekey` works.

## Troubleshooting

If `just rekey-update-masterkeys` fails with:

```text
Identity file not found: ~/.config/agenix/master.agekey
```

create/rotate the identity again:

```bash
FORCE=true just master-key-create
```

If it fails with:

```text
No matching keys found
```

you rotated to a new key before source secrets were migrated. Restore the old
identity temporarily, run:

```bash
just rekey-update-masterkeys
just rekey
```

then switch back to the new identity.

If the old identity is lost but a deployed machine still has runtime plaintext
secrets, recover source `.age` files with:

```bash
just secret-recover-from-runtime
just rekey
```
