# Homelab Module Contract

This repository splits homelab configuration into two layers.

## 1) Reusable modules (`modules/nixos/homelab/*`)

Reusable modules must:

- avoid personal values (domains, emails, hostnames, provider endpoints)
- avoid implicit service deployment (`services.<name>.enable = true`)
- prefer safe `lib.mkDefault` values only
- avoid cross-module orchestration through custom option namespaces
- gate side-effectful wiring (`users`, `groups`, `tmpfiles`, `serviceConfig`) on
  `config.services.<name>.enable`

## 2) Host composition (`configs/nixos/**`)

Host modules must own:

- service enablement
- stack topology and integration wiring
- domain/ACME settings
- VPN provider details and policy routing
- host-specific storage layout and permissions
- secret references for each host profile

## Shared host integration model

Shared host-side modules live in `configs/nixos/_shared/homelab/`.

- `stack-values.nix`: canonical service inventory and shared stack constants
- `services.nix`: enables and baseline service values for the host profile
- `ingress.nix`: Caddy + Homepage generated from `stack-values.nix`
- `network.nix`: VPN and policy-routing config using upstream NixOS options
- `storage.nix`: shared media/downloads group and directory model

Per-host wrappers in `configs/nixos/home-server/modules/` and
`configs/nixos/home-server-vm/modules/` import these shared modules with a
`profile` argument.
