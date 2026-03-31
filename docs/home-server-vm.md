# Home Server VM Testing

This document covers the current, supported local VM workflow on macOS.

There is now a single VM config: `home-server-vm`.

Historical notes, old experiment matrices, and superseded failures are archived
in `docs/archive/home-server-vm-history.md`.

## Current status (2026-03-29)

- Smoke checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Parity checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Smoke now gates on `SSH + Caddy + /healthz`.
- Newly re-enabled and re-tested in parity: `homepage-dashboard`, `vaultwarden`,
  `bazarr`, `lidarr`, `readarr`, `flaresolverr`, and `seerr`.
- For now, the supported vmnet path is `vmnet-helper`.
- The old `home-server-vm-parity` config has been removed; parity is now only a
  check profile against `home-server-vm`.
- SSH is back to key-based auth in the VM path, and `fail2ban` is enabled again.
- The VM now runs Mullvad WireGuard, VPN policy routing, and qBittorrent VPN
  binding in parity runs.
- HTTPS ingress now uses Caddy with NixOS ACME DNS-01 via Cloudflare.

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
  - HTTPS health: `https://127.0.0.1:8443/healthz` (use `-k` for direct IP
    checks)
- vfkit checks use guest-ip mode (`SSH :22`, `HTTPS :443`) and resolve IP from
  `${run_dir}/guest-ip` and DHCP leases.

## Browser access matrix

- QEMU hostfwd (`just home-server-vm-run-macos`):
  - ingress is on host forwarded port (`${run_dir}/ingress-port`, usually `8443`)
  - use `https://home.ianholloway.com:<ingress-port>/`
  - app subdomains also require the forwarded port in browser tests,
    for example `https://seerr.home.ianholloway.com:<ingress-port>/`
  - homepage app links now redirect to subdomain hosts while preserving that same
    forwarded port
- vfkit NAT/vmnet (`just home-server-vm-run-macos-vfkit*`):
  - checks run in `guest-ip` mode on standard `:443`
  - use guest IP routing for browser tests (`https://<subdomain>.home.ianholloway.com/`)
    with local DNS pointing to the guest IP

### DNS requirements for subdomain ingress

- Ingress is subdomain-based, not path-prefix based.
- Apex-only DNS (`home.ianholloway.com` only) is not enough for app routes.
- Configure wildcard or explicit local DNS records for app hosts, for example:
  - `*.home.ianholloway.com -> <local test target>`
  - or explicit records for `seerr.home.ianholloway.com`,
    `jellyfin.home.ianholloway.com`, etc.

For your UniFi setup (laptop-hosted VM testing), this means:

- keep `home.ianholloway.com -> <laptop-fixed-ip>`
- add `*.home.ianholloway.com -> <laptop-fixed-ip>`

Without subdomain DNS, homepage can render, but redirected app links will fail
in browser with "Server Not Found".

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

| Path                                               | Profile      | Result | Notes                                                                                             |
| -------------------------------------------------- | ------------ | ------ | ------------------------------------------------------------------------------------------------- |
| QEMU (`run-macos` + `check-fast`)                  | smoke        | pass   | `/healthz` stable and homepage passes in recent runs.                                             |
| QEMU (`run-macos` + `check-parity-fast`)           | parity       | pass   | media probes, guest service checks, Caddy ingress, and VPN user egress checks pass.               |
| vfkit NAT (`run-macos-vfkit` + `check-vfkit-fast`) | smoke        | pass   | same smoke gating contract as QEMU.                                                               |
| vfkit NAT parity                                   | parity       | pass   | media probes, guest service checks, Caddy ingress, and VPN user egress checks pass.               |
| vfkit vmnet-shared (`VMNET_PROVIDER=helper`)       | smoke/parity | pass   | validated with the packaged helper path, including VPN user egress checks and Caddy+ACME ingress. |
| vfkit vmnet-host (`VMNET_PROVIDER=helper`)         | smoke        | pass   | revalidated with the packaged helper path.                                                        |

## Smoke-check behavior

`scripts/check-home-server-vm.sh`:

- waits for SSH,
- waits for ingress readiness (`/healthz`),
- checks HTTP endpoints by profile,
- checks guest services over SSH when batch SSH is available, including
  `fail2ban` and `caddy` in the base service set,
- runs service-user egress checks in parity mode when passwordless sudo exists.

Media probes accept auth challenge statuses by default (`401`, `403`) to avoid
false negatives for intentionally protected endpoints.

`flaresolverr` is checked as a guest service/listener in parity mode, not as a
public route.

Apps are validated via per-app subdomains instead of NGINX path-prefix routes.

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
- `HOME_SERVER_VM_BASE_DOMAIN` (default `home.ianholloway.com`)
- `HOME_SERVER_VM_PRIMARY_HOST` (default equals base domain)
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
- VM profile now additionally allows password SSH auth for local recovery,
  while still keeping key-based auth enabled.
- `fail2ban` is enabled again in the VM and included in guest service checks.
- `homelab-network` is imported and active in the VM.
- HTTPS ingress uses Caddy with ACME DNS-01 certificate issuance.
- Mullvad WireGuard, VPN nftables/policy routing, and qBittorrent binding are
  enabled and validated in parity checks.
- qBittorrent, NZBGet, and Prowlarr are all verified to egress through Mullvad.
- Reverse path filtering remains `loose` by design to support asymmetric
  policy-routing paths.

## Troubleshooting

- If vfkit vmnet launch fails, check runner logs in `${run_dir}`:
  - `vmnet-provider.log`
  - `vmnet.json`
  - `vmnet-helper.json` (legacy compatibility output)
- If packaged `vmnet-helper` is used for the first time, the wrapper signs a
  cached copy under `~/Library/Caches/nix-conf-server/` before launch.
- If HTTPS is delayed on first boot, inspect ACME unit status and logs.
- If Caddy starts before Jellyfin is fully ready on vfkit vmnet runs, parity
  checks now wait briefly and retry failed media endpoints after guest service
  checks.
- The repo-root `*.qcow2` and `*.raw` VM images are disposable local artifacts.
  If removed, the runners recreate them automatically on the next launch.
- If guest IP resolution is wrong due stale leases, set
  `HOME_SERVER_VM_GUEST_IP_PREFIX` (for example `192.168.105`).
- If checks fail immediately, confirm VM is already running in another terminal.
- If homepage (`/`) fails but `/healthz` passes in smoke, this is expected and
  non-gating unless `HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=1` is set.
- `scripts/check-home-server-vm.sh` now includes a DNS preflight warning when
  apex resolves but a sample app subdomain does not. Disable with
  `HOME_SERVER_VM_DNS_PREFLIGHT=0`.
- `scripts/check-home-server-vm.sh` auto-selects connect mode in `auto` based on
  `${run_dir}/runner-mode`:
  - `vfkit-*` -> `guest-ip`
  - otherwise -> `hostfwd`
- checker now auto-falls back to insecure TLS mode for local VM checks when
  certificate trust fails (for example LE rate-limit fallback certs on first
  boot); disable with `HOME_SERVER_VM_TLS_AUTO_FALLBACK=0`.

## NixOS wiring test

Linux-only integration wiring check remains available through:

```bash
nix flake check --no-allow-import-from-derivation
```

On macOS this specific check is skipped by design.
