# SSH from desktop to MacBook

The desktop configuration now provides `ssh macbook` and `ssh macbook-pro-m4`.
Both select `<USER>@<MACBOOK-HOSTNAME>` and the desktop's existing
`~/.ssh/id_ed25519` key. The MacBook configuration enables Apple's SSH server
and authorizes that desktop public key for `user`.

The desktop pins the MacBook's existing Ed25519 host key under the stable
`macbook` alias. This is the same public key already declared for the MacBook's
nix-seal host identity. A different host key is rejected even if the IP address
changes. Private keys are not copied between machines.

## Apply on both machines

These changes are saved in Nix configuration. They have not been activated.
The first MacBook activation must happen locally because SSH is not yet set up.

On the MacBook, from this checkout with these changes available:

```sh
sudo darwin-rebuild switch --flake .#macbook-pro-m4
```

On the desktop, after reviewing the checkout's other pending changes:

```sh
nh os switch . -H desktop
ssh macbook
```

The desktop uses resolve-only mDNS on its physical wired and wireless links to
find `<MACBOOK-HOSTNAME>`. It accepts mDNS replies from private IPv4 or link-local
IPv6 peers on those interfaces. Avahi and LLMNR remain disabled. This requires
both machines to share a network that permits Bonjour traffic.

UniFi Site Manager could not be inspected because the app's browser runtime
was missing its required `browser-service.mjs` file. No DHCP reservations or
other UniFi settings were changed. The Bonjour configuration therefore remains
the address-discovery method; a reserved LAN address can replace `HostName`
later without changing the host-key pin.

If the network blocks Bonjour, use the MacBook's current LAN address while
retaining the pinned host key and client settings:

```sh
ssh -o HostName=MACBOOK_LAN_IP macbook
```

The MacBook accepts public-key authentication for `user`. Root login and
password authentication are disabled. Normal user SSH and interactive `sudo`
provide the starting point for a later deploy-rs configuration. This change
does not grant passwordless sudo or configure a deploy-rs node for the MacBook.

## Validation

The evaluated MacBook Bonjour name, SSH account, authorized public key, and
desktop host-key pin agree. Nix evaluates the complete macOS system derivation.
OpenSSH accepts the client and daemon configuration; nftables accepts the mDNS
rules in an isolated network namespace. Modified Nix files pass `nixfmt`.

The broader desktop configuration contract in `flake/deploy.nix` also evaluates
successfully with the reviewed integration changes. No desktop activation or
live MacBook connection was attempted. The MacBook was unavailable, and native
macOS checks were skipped at the user's request.
