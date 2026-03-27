# Secrets Workflow

This repo uses `agenix` for runtime decryption and `secretctl` for SSH-recipient
encryption.

## Key points

- No master keys are used.
- Canonical ciphertext lives under `secrets/<owner-group>/`.
- Each config declares its own `secrets.publicKey` and the owner groups it
  belongs to.
- Within each owner group, the group root, `home/`, and `system/` control which
  configs receive a secret.
- Forks can reuse the same owner-group names and replace only their own config
  keys.

## Config metadata

Each host or home config defines:

```nix
secrets = {
  publicKey = "ssh-ed25519 ...";
  extraPublicKeys = [
    "ssh-ed25519 ..."
  ];
  groups = [ "IanHollow" ];
};
```

- `publicKey` is the SSH public key for that concrete target.
- `extraPublicKeys` is an optional list of additional SSH public keys for that
  same target (for example a temporary VM host key during migration).
- `groups` is the list of top-level owner groups that target should receive.

`publicKey` remains required. If `extraPublicKeys` is omitted, it defaults to an
empty list.

## Secret layout and IDs

Example layout:

```text
secrets/IanHollow/
  nix-access-tokens.age
  home/
    ianmh/
      gitconfig-userName.age
  system/
    all-systems-secret.age
    nixos/
      all-nixos-secret.age
      desktop/
        some-system-secret.age
    darwin/
      all-darwin-secret.age
      macbook-pro-m4/
        another-system-secret.age
```

Example IDs:

- `secrets/IanHollow/nix-access-tokens.age` -> `IanHollow.nix-access-tokens`
- `secrets/IanHollow/home/ianmh/gitconfig-userName.age` ->
  `IanHollow.home.ianmh.gitconfig-userName`
- `secrets/IanHollow/system/nixos/desktop/some-system-secret.age` ->
  `IanHollow.system.nixos.desktop.some-system-secret`
- `secrets/IanHollow/system/darwin/all-darwin-secret.age` ->
  `IanHollow.system.darwin.all-darwin-secret`

The runtime `agenix` secret name remains the file stem, so
`secrets/IanHollow/home/ianmh/gitconfig-userName.age` is still accessed as
`config.age.secrets.gitconfig-userName`.

## Scope rules

Inside each owner group:

- `<group>/*.age` applies to all homes and systems in that owner group.
- `home/*.age` applies to all homes in that owner group.
- `home/<username>/*.age` applies only to homes with that username.
- `system/*.age` applies to all systems in that owner group.
- `system/nixos/*.age` applies to all NixOS systems in that owner group.
- `system/darwin/*.age` applies to all Darwin systems in that owner group.
- `system/nixos/<config-name>/*.age` applies only to that NixOS config folder.
- `system/darwin/<config-name>/*.age` applies only to that Darwin config folder.

Extra nested folders under the group root are not used for shared secrets; use
the group root directly. Extra nested folders under `home/<username>/`, or
`system/<platform>/<config-name>/` are allowed for organization.

## Create or update secrets

- Encrypt from plaintext file:
  - `just secret-encrypt <secret-id> <path-to-plaintext>`
- Edit secret with your editor:
  - `just secret-edit <secret-id>`
- View decrypted content:
  - `just secret-view <secret-id>`
- Preview recipients:
  - `just secret-recipients <secret-id>`

## Validate before commit

- `just secret-lint`
- `just secret-check`

## Rotation pattern

To avoid lockout when rotating keys:

1. Add the new public key to the relevant config.
   - If keeping the old key for the same target, place the additional key in
     `secrets.extraPublicKeys`.
2. Keep the old key temporarily on another config that should still decrypt the
   same secrets.
3. Run `just secret-reencrypt --all`.
4. Verify access with the new key.
5. Remove the old key and re-encrypt again.
