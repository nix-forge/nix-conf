# Home Server VM Testing

This document covers the current, supported local VM workflow on macOS.

There is now a single VM config: `home-server-vm`.

Historical notes, old experiment matrices, and superseded failures are archived
in `docs/archive/home-server-vm-history.md`.

## Current status (2026-03-29)

- Smoke checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Parity checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Smoke still gates on `SSH + nginx + /healthz`, but the homepage now also
  passes in recent local runs.
- Newly re-enabled and re-tested in parity: `homepage-dashboard`, `vaultwarden`,
  `bazarr`, `lidarr`, `readarr`, `flaresolverr`, and `seerr`.
- For now, the supported vmnet path is `vmnet-helper`.
- The old `home-server-vm-parity` config has been removed; parity is now only a
  check profile against `home-server-vm`.
- SSH is back to key-based auth in the VM path, and `fail2ban` is enabled again.
- The VM now imports and runs the network stack end-to-end: `tailscaled`,
  Mullvad WireGuard, VPN policy routing, and qBittorrent VPN binding are all
  active in parity runs.
- `tailscale-cert` now works in the VM and the Tailscale HTTPS cert is issued
  successfully for the VM node.

## Check profiles

- `smoke`: fast local loop for SSH + ingress + core checks.
- `parity`: wider app/service regression against the same `home-server-vm`
  config.

## Quick start

Smoke (QEMU):

```bash
just home-server-vm-run-macos
just home-server-vm-check-fast
```

Smoke (vfkit NAT):

```bash
just home-server-vm-run-macos-vfkit
just home-server-vm-check-vfkit-fast
```

Parity (QEMU, same VM config):

```bash
just home-server-vm-run-macos
just home-server-vm-check-parity-fast
```

Parity (vfkit NAT, same VM config):

```bash
just home-server-vm-run-macos-vfkit
just home-server-vm-check-vfkit-parity-fast
```

vfkit vmnet shared:

```bash
just home-server-vm-run-macos-vfkit-vmnet-shared
just home-server-vm-check-vfkit-fast
```

vfkit vmnet host:

```bash
just home-server-vm-run-macos-vfkit-vmnet-host
just home-server-vm-check-vfkit-fast
```

vfkit vmnet shared parity:

```bash
HOME_SERVER_VM_NET_MODE=vmnet-shared HOME_SERVER_VM_VMNET_PROVIDER=helper ./scripts/run-home-server-vm-macos-vfkit.sh
HOME_SERVER_VM_CONNECT_MODE=guest-ip HOME_SERVER_VM_PROFILE=parity ./scripts/check-home-server-vm.sh
```

## Host access

- QEMU default access:
  - SSH: `ssh -p 2222 testadmin@127.0.0.1`
  - HTTP health: `http://127.0.0.1:8080/healthz`
- vfkit checks use guest-ip mode (`SSH :22`, `HTTP :8080`) and resolve IP from
  `${run_dir}/guest-ip` and DHCP leases.

## vmnet on macOS 26

### Recommended setup

`vmnet-helper` is now packaged from source in this repo.

You can use it in either of these ways:

```bash
nix build .#vmnet-helper
```

or:

```bash
nix develop
```

The vfkit runner also falls back to `.#vmnet-helper` automatically if
`vmnet-helper` is not already on `PATH`.

### Provider selection

For `HOME_SERVER_VM_NET_MODE=vmnet-shared|vmnet-host`, use
`HOME_SERVER_VM_VMNET_PROVIDER=helper` for the documented path.

You can override helper binary discovery with:

- `HOME_SERVER_VM_VMNET_BIN`
- `HOME_SERVER_VM_VMNET_HELPER_BIN` (legacy-compatible)

## Validation matrix (latest)

| Path                                               | Profile      | Result | Notes                                                                                                  |
| -------------------------------------------------- | ------------ | ------ | ------------------------------------------------------------------------------------------------------ |
| QEMU (`run-macos` + `check-fast`)                  | smoke        | pass   | `/healthz` stable and homepage passes in recent runs.                                                  |
| QEMU (`run-macos` + `check-parity-fast`)           | parity       | pass   | media probes, guest service checks, Tailscale autoconnect, and VPN user egress checks pass.            |
| vfkit NAT (`run-macos-vfkit` + `check-vfkit-fast`) | smoke        | pass   | same smoke gating contract as QEMU.                                                                    |
| vfkit NAT parity                                   | parity       | pass   | media probes, guest service checks, Tailscale autoconnect, and VPN user egress checks pass.            |
| vfkit vmnet-shared (`VMNET_PROVIDER=helper`)       | smoke/parity | pass   | validated with the packaged helper path, including VPN user egress checks and the Tailscale cert path. |
| vfkit vmnet-host (`VMNET_PROVIDER=helper`)         | smoke        | pass   | revalidated with the packaged helper path.                                                             |

## Smoke-check behavior

`scripts/check-home-server-vm.sh`:

- waits for SSH,
- waits for ingress readiness (`/healthz`),
- checks HTTP endpoints by profile,
- checks guest services over SSH when batch SSH is available, including
  `fail2ban` and `tailscaled` in the base service set,
- runs service-user egress checks in parity mode when passwordless sudo exists.

Media probes accept auth challenge statuses by default (`401`, `403`) to avoid
false negatives for intentionally protected endpoints.

`flaresolverr` is checked as a guest service/listener in parity mode, not as an
nginx-exposed public route.

`seerr` is served at `/seerr/`, with `/jellyseerr/` redirected for
compatibility.

VPN user egress checks verify that `qbittorrent`, `nzbget`, and `prowlarr` reach
the public internet through the Mullvad WireGuard path.

Service group model checks now assert:

- `qbittorrent`, `nzbget`, and Arr services have `downloads` access,
- Arr services plus `jellyfin` have `media` access,
- `prowlarr` is not in either `downloads` or `media`.

## Key environment variables

Checker:

- `HOME_SERVER_VM_PROFILE` (`smoke` or `parity`)
- `HOME_SERVER_VM_CONNECT_MODE` (`auto`, `hostfwd`, `guest-ip`)
- `HOME_SERVER_VM_GUEST_IP`, `HOME_SERVER_VM_GUEST_IP_FILE`
- `HOME_SERVER_VM_GUEST_IP_PREFIX`
- `HOME_SERVER_VM_MEDIA_ALLOWED_HTTP_CODES`
- `HOME_SERVER_VM_MEDIA_RETRY_AFTER_SERVICE_DELAY`

QEMU runner (`scripts/run-home-server-vm-macos.sh`):

- `HOME_SERVER_VM_NET_BACKEND` (`user` only)
- `HOME_SERVER_VM_REBUILD_STORE_IMAGE`
- `HOME_SERVER_VM_DISK_CACHE`, `HOME_SERVER_VM_NET_DEVICE`

vfkit runner (`scripts/run-home-server-vm-macos-vfkit.sh`):

- `HOME_SERVER_VM_NET_MODE` (`nat`, `vmnet-shared`, `vmnet-host`)
- `HOME_SERVER_VM_VMNET_PROVIDER` (`helper` recommended)
- `HOME_SERVER_VM_VMNET_BIN`
- `HOME_SERVER_VM_VMNET_HELPER_BIN` (legacy)
- `HOME_SERVER_VM_VMNET_USE_SUDO` (`auto`, `0`, `1`)
- `HOME_SERVER_VM_VMNET_INTERFACE_ID`
- `HOME_SERVER_VM_REBUILD_RAW`, `HOME_SERVER_VM_REBUILD_STORE_IMAGE`

## Supported command matrix

Primary regression paths:

- `just home-server-vm-run-macos` + `just home-server-vm-check-fast`
- `just home-server-vm-run-macos` + `just home-server-vm-check-parity-fast`
- `just home-server-vm-run-macos-vfkit` + `just home-server-vm-check-vfkit-fast`
- `just home-server-vm-run-macos-vfkit` +
  `just home-server-vm-check-vfkit-parity-fast`
- `HOME_SERVER_VM_NET_MODE=vmnet-shared HOME_SERVER_VM_VMNET_PROVIDER=helper ./scripts/run-home-server-vm-macos-vfkit.sh` +
  parity check script

Secondary/manual validation:

- vfkit vmnet-host smoke with `HOME_SERVER_VM_VMNET_PROVIDER=helper`

## Security and network notes

- SSH access now follows the main host more closely: key-based auth only over
  SSH, while the console password remains available for local recovery.
- `fail2ban` is enabled again in the VM and included in guest service checks.
- `homelab-network` is imported and active in the VM.
- Tailscale autoconnect works with the rotated direct auth key.
- Tailscale HTTPS certificate issuance works, and nginx can use the issued cert
  on 443.
- Mullvad WireGuard, VPN nftables/policy routing, and qBittorrent binding are
  enabled and validated in parity checks.
- qBittorrent, NZBGet, and Prowlarr are all verified to egress through Mullvad.
- Reverse path filtering remains `loose` by design to support asymmetric
  policy-routing and tailscale traffic paths.

## Troubleshooting

- If vfkit vmnet launch fails, check runner logs in `${run_dir}`:
  - `vmnet-provider.log`
  - `vmnet.json`
  - `vmnet-helper.json` (legacy compatibility output)
- If packaged `vmnet-helper` is used for the first time, the wrapper signs a
  cached copy under `~/Library/Caches/nix-conf-server/` before launch.
- If `tailscaled-autoconnect.service` fails, check `vm-local-secrets.service`
  first to confirm the local secret disk mounted and decrypted the auth key.
- If nginx starts before Jellyfin is fully ready on vfkit vmnet runs, parity
  checks now wait briefly and retry failed media endpoints after guest service
  checks.
- The repo-root `*.qcow2` and `*.raw` VM images are disposable local artifacts.
  If removed, the runners recreate them automatically on the next launch.
- If guest IP resolution is wrong due stale leases, set
  `HOME_SERVER_VM_GUEST_IP_PREFIX` (for example `192.168.105`).
- If checks fail immediately, confirm VM is already running in another terminal.
- If homepage (`/`) fails but `/healthz` passes in smoke, this is expected and
  non-gating unless `HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=1` is set.

## Not in scope yet

- Frigate parity in the local VM

## NixOS wiring test

Linux-only integration wiring check remains available through:

```bash
nix flake check --no-allow-import-from-derivation
```

On macOS this specific check is skipped by design.
