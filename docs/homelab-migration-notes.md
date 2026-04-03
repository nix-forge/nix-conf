# Homelab Migration Notes

## Breaking changes

### Removed custom option tree

The custom option tree below has been removed:

- `homelab.network.vpnPolicyRouting.*`

Policy routing and VPN egress filtering now live in host composition using
upstream options only:

- `systemd.network.config.routeTables`
- `systemd.network.networks.*.routes`
- `systemd.network.networks.*.routingPolicyRules`
- `networking.nftables.tables.*`

### Service auto-enable removed from reusable homelab modules

Importing `modules/nixos/homelab/*` no longer enables services automatically.
Service enablement now happens in host composition modules.

## New host-shared composition modules

Added under `configs/nixos/_shared/homelab/`:

- `stack-values.nix`
- `services.nix`
- `ingress.nix`
- `network.nix`
- `storage.nix`

## Host wrappers

Host wrapper modules now import shared profile modules:

- `configs/nixos/home-server/modules/host-homelab-*.nix`
- `configs/nixos/home-server-vm/modules/host-homelab-*.nix`

## VM user password handling

`configs/nixos/home-server-vm/modules/users.nix` now uses `hashedPasswordFile`
from agenix instead of `initialPassword = "changeme"`.

## Validation checklist

- `just check`
- `just secret-check`
- `nix eval .#nixosConfigurations.home-server.config.networking.nftables.tables`
- `nix eval .#nixosConfigurations.home-server-vm.config.services.caddy.virtualHosts`
