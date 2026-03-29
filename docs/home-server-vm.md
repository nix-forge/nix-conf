# Home Server VM Testing

This document covers the current, supported local VM workflow on macOS.

Historical notes, old experiment matrices, and superseded failures are archived
in `docs/archive/home-server-vm-history.md`.

## Current status (2026-03-29)

- Smoke checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Parity checks pass on QEMU, vfkit NAT, and vfkit vmnet-shared.
- Smoke still gates on `SSH + nginx + /healthz`, but the homepage now also
  passes in recent local runs.
- Newly re-enabled and re-tested in parity: `homepage-dashboard`,
  `vaultwarden`, `bazarr`, `lidarr`, and `readarr`.
- For now, the supported vmnet path is `vmnet-helper`; `vmnet-broker` remains
  packaged but is not yet the documented/validated host setup.

## Profiles

- `home-server-vm`: smoke profile for fast local loops.
- `home-server-vm-parity`: wider media-stack parity profile, still non-gating
  for day-to-day smoke loops.

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

Parity (QEMU):

```bash
just home-server-vm-parity-run-macos
just home-server-vm-parity-check-fast
```

Parity (vfkit NAT):

```bash
just home-server-vm-parity-run-macos-vfkit
just home-server-vm-parity-check-vfkit-fast
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

## Host access

- QEMU default access:
  - SSH: `ssh -p 2222 testadmin@127.0.0.1`
  - HTTP health: `http://127.0.0.1:8080/healthz`
- vfkit checks use guest-ip mode (`SSH :22`, `HTTP :8080`) and resolve IP from
  `${run_dir}/guest-ip` and DHCP leases.

## vmnet on macOS 26

### Recommended setup (vmnet-helper for now)

`vmnet-helper` is now packaged from source in this repo.

You can use it in either of these ways:

```bash
nix build .#vmnet-helper
```

or:

```bash
nix develop
```

On the MBP Darwin host config, `vmnet-helper` is also included in
`environment.systemPackages`, so `just darwin-switch macbook-pro-m4` will
install it system-wide.

The package wrapper signs a per-user cached copy with the upstream
entitlements on first run, because the Nix store itself is immutable.

The vfkit runner also falls back to `.#vmnet-helper` automatically if
`vmnet-helper` is not already on `PATH`.

`vmnet-broker` is still packaged in the repo, but the nix-darwin activation
path for installing and bootstrapping it is not finished or documented as
supported yet.

### Provider selection

For `HOME_SERVER_VM_NET_MODE=vmnet-shared|vmnet-host`, runner provider logic is:

- `HOME_SERVER_VM_VMNET_PROVIDER=auto` (default)
  - macOS 26+: try broker mode first (`vmnet-helper --network ...`), then
    helper operation mode fallback.
- `HOME_SERVER_VM_VMNET_PROVIDER=broker`: force broker mode.
- `HOME_SERVER_VM_VMNET_PROVIDER=helper`: force helper operation mode.

For now, use `HOME_SERVER_VM_VMNET_PROVIDER=helper` if you want the most
predictable documented path.

You can override helper binary discovery with:

- `HOME_SERVER_VM_VMNET_BIN`
- `HOME_SERVER_VM_VMNET_HELPER_BIN` (legacy-compatible)

## Validation matrix (latest)

| Path | Profile | Result | Notes |
|---|---|---|---|
| QEMU (`run-macos` + `check-fast`) | smoke | pass | `/healthz` stable; `/` may return `502` and is non-gating in smoke. |
| QEMU (`parity-run-macos` + `parity-check-fast`) | parity | pass | media probes + guest service checks pass, including `vaultwarden`, `bazarr`, `lidarr`, and `readarr`. |
| vfkit NAT (`run-macos-vfkit` + `check-vfkit-fast`) | smoke | pass | same smoke gating contract as QEMU. |
| vfkit NAT parity | parity | pass | media probes + guest service checks pass, including newly re-enabled app services. |
| vfkit vmnet-shared (`VMNET_PROVIDER=helper`) | smoke/parity | pass | validated with the packaged helper path. |
| vfkit vmnet-host (`VMNET_PROVIDER=helper`) | smoke | pass | revalidated with the packaged helper path. |
| vfkit broker-forced vmnet | smoke/parity | not validated | broker packaging exists, but system install/bootstrap is intentionally deferred. |

## Smoke-check behavior

`scripts/check-home-server-vm.sh`:

- waits for SSH,
- waits for ingress readiness (`/healthz`),
- checks HTTP endpoints by profile,
- checks guest services over SSH when batch SSH is available,
- runs service-user egress checks in parity mode when passwordless sudo exists.

Media probes accept auth challenge statuses by default (`401`, `403`) to avoid
false negatives for intentionally protected endpoints.

## Key environment variables

Checker:

- `HOME_SERVER_VM_PROFILE` (`smoke` or `parity`)
- `HOME_SERVER_VM_CONNECT_MODE` (`auto`, `hostfwd`, `guest-ip`)
- `HOME_SERVER_VM_GUEST_IP`, `HOME_SERVER_VM_GUEST_IP_FILE`
- `HOME_SERVER_VM_GUEST_IP_PREFIX`
- `HOME_SERVER_VM_MEDIA_ALLOWED_HTTP_CODES`

QEMU runner (`scripts/run-home-server-vm-macos.sh`):

- `HOME_SERVER_VM_NET_BACKEND` (`user` only)
- `HOME_SERVER_VM_REBUILD_STORE_IMAGE`
- `HOME_SERVER_VM_DISK_CACHE`, `HOME_SERVER_VM_NET_DEVICE`

vfkit runner (`scripts/run-home-server-vm-macos-vfkit.sh`):

- `HOME_SERVER_VM_NET_MODE` (`nat`, `vmnet-shared`, `vmnet-host`)
- `HOME_SERVER_VM_VMNET_PROVIDER` (`auto`, `broker`, `helper`)
- `HOME_SERVER_VM_VMNET_BIN`
- `HOME_SERVER_VM_VMNET_HELPER_BIN` (legacy)
- `HOME_SERVER_VM_VMNET_USE_SUDO` (`auto`, `0`, `1`)
- `HOME_SERVER_VM_VMNET_INTERFACE_ID`
- `HOME_SERVER_VM_REBUILD_RAW`, `HOME_SERVER_VM_REBUILD_STORE_IMAGE`

## Troubleshooting

- If vfkit vmnet launch fails, check runner logs in `${run_dir}`:
  - `vmnet-provider.log`
  - `vmnet.json`
  - `vmnet-helper.json` (legacy compatibility output)
- If packaged `vmnet-helper` is used for the first time, the wrapper signs a
  cached copy under `~/Library/Caches/nix-conf-server/` before launch.
- The repo-root `*.qcow2` and `*.raw` VM images are disposable local artifacts.
  If removed, the runners recreate them automatically on the next launch.
- If guest IP resolution is wrong due stale leases, set
  `HOME_SERVER_VM_GUEST_IP_PREFIX` (for example `192.168.105`).
- If checks fail immediately, confirm VM is already running in another terminal.
- If homepage (`/`) fails but `/healthz` passes in smoke, this is expected and
  non-gating unless `HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=1` is set.

## Not in scope yet

- `vmnet-broker` system installation and launchd bootstrap via nix-darwin
- Tailscale / WireGuard / Mullvad-bound behavior in the VM
- Frigate parity in the local VM

## NixOS wiring test

Linux-only integration wiring check remains available through:

```bash
nix flake check --no-allow-import-from-derivation
```

On macOS this specific check is skipped by design.
