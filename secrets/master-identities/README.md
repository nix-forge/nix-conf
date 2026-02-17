# Master Identity Setup

This repository keeps only public recipient data in git:

- `main.pub`: primary master public key
- `team-pubkeys.nix`: additional public recipients

The private master identity used by `agenix-rekey` must stay outside the repo.

## Recommended Path

Store a passphrase-protected age identity at:

- Linux: `~/.config/agenix/master.age`
- macOS: `~/.config/agenix/master.age`

For hosts where you administer secrets, set `masterIdentityPath` in the host
config to this path.

For standalone Home Manager configs, `masterIdentityPath` is optional. Set it if
that home will run `agenix rekey`; otherwise it can be omitted.

For Home Manager users attached to NixOS/darwin, the system-level
`masterIdentityPath` is authoritative (including `null` to explicitly disable a
home-provided path).

For first-time NixOS installs from a live ISO, follow:

- `docs/nixos-install-preseeded-host-key.md`

Live ISO installs do not require `master.age`; they require the target host SSH
keypair to be preseeded and secrets already rekeyed for that host key.

## Security Requirements

- Never commit private keys to git.
- Keep permissions strict:
  - `chmod 700 ~/.config/agenix`
  - `chmod 600 ~/.config/agenix/master.age`
- Use a strong passphrase for `master.age`.
