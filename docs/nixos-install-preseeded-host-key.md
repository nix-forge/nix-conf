# NixOS Install with Preseeded Host Key (agenix)

This repository expects each NixOS host to have a specific SSH host public key
(`sshPubKey` in that host's config). Secrets are encrypted for that key.

For a fresh install from a live ISO, preseed the matching host keypair before
running `nixos-install`.

## Why the master key is not needed on the ISO

The age master identity (`~/.config/agenix/master.age`) is only needed to
encrypt/rekey secrets. Decryption during install/activation uses the host SSH
private key (`/etc/ssh/ssh_host_ed25519_key`).

So the install machine only needs:

- a flake revision where secrets were already rekeyed for the target host key
- the target host SSH keypair preseeded into `/mnt/etc/ssh`

## 1. On an admin machine: prepare host key and rekey

Use a trusted machine that has your master age identity:

Use an Ed25519 host key:

```bash
ssh-keygen -t ed25519 -f ./ssh_host_ed25519_key -N ""
```

Record the public key:

```bash
cat ./ssh_host_ed25519_key.pub
```

Set the host's `sshPubKey` in repo config to this exact value.

Rekey secrets in the repo:

```bash
just rekey
```

Then commit/push the updated repo state (or otherwise make it available to the
installer environment).

## 2. Boot installer and prepare `/mnt`

From the live ISO:

1. Partition/mount disks (for this repo, use your normal disko workflow).
2. Ensure target root is mounted at `/mnt`.

## 3. Preseed host key into target root

Copy private and public key into the target filesystem:

```bash
install -d -m 0755 /mnt/etc/ssh
install -m 0600 ./ssh_host_ed25519_key /mnt/etc/ssh/ssh_host_ed25519_key
install -m 0644 ./ssh_host_ed25519_key.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

Set ownership:

```bash
chown root:root /mnt/etc/ssh/ssh_host_ed25519_key /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

## 4. Install

Run:

```bash
nixos-install --flake .#desktop
```

Replace `desktop` with your target host config name.

## 5. If you cannot preseed ahead of time

Fallback flow:

1. On the ISO, generate `/mnt/etc/ssh/ssh_host_ed25519_key`.
2. Export `/mnt/etc/ssh/ssh_host_ed25519_key.pub` to your admin machine.
3. Update host `sshPubKey`, run `just rekey`, and make the updated repo
   available on the installer.
4. Run `nixos-install --flake .#<host>`.

## 6. What the preflight check enforces

During activation, this repo validates:

- `/etc/ssh/ssh_host_ed25519_key.pub` exists and is readable.
- Its `<type> <base64>` matches configured `sshPubKey` for the host.

If it does not match, activation fails with a message that points back to this
guide.

## Security Notes

- Never commit private host keys.
- Transfer keys to install environment over a secure channel only.
- Treat generated host private keys like root credentials.
