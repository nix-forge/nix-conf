# Media Server VM on MBP

This repo includes two VM test hosts for local validation on macOS:

- `media-server-vm-parity` (`configs/nixos/media-server-vm-parity`,
  `x86_64-linux`)
- `media-server-vm-smoke` (`configs/nixos/media-server-vm-smoke`,
  `aarch64-linux`)

## Why a separate VM host

The production `media-server` host includes bare-metal assumptions (disko,
static networking, external integrations). The VM host isolates those concerns
and keeps production config unchanged.

## Quick start

From repo root, choose a profile:

```bash
# parity profile (x86_64-linux on MBP, slower but architecture parity)
just media-vm-build parity
just media-vm-run parity

# smoke profile (aarch64-linux on MBP, faster local iteration)
just media-vm-build smoke
just media-vm-run smoke
```

In another terminal:

```bash
just media-vm-test smoke
```

For parity validation:

```bash
just media-vm-test parity
```

## Reset the VM image

If networking/disk layout changes or boot gets stuck, reset artifacts:

```bash
just media-vm-reset parity
```

Then rebuild/run again.

## Forwarded ports

- `2222 -> guest 22` (SSH)
- `8080 -> guest 80` (Traefik HTTP)
- `8443 -> guest 443` (Traefik HTTPS)
- `8096 -> guest 8096` (Jellyfin direct)
- `5055 -> guest 5055` (Jellyseerr direct)

## Notes and caveats

- `parity` uses `x86_64-linux` on Apple Silicon; slower but closer to production
  architecture.
- `smoke` uses `aarch64-linux`; faster iteration but not architecture parity.
- Both VM profiles now reuse the same main media-server site, secrets, and
  exposure modules for service parity; VM differences are isolated to VM runtime
  and VM override modules.
- VM overrides supply local fixture secret files so secret-backed services can
  boot deterministically during VM tests.
- VM torrent validation keeps the qBittorrent-to-Gluetun namespace topology, but
  uses a lightweight VM-side mock Gluetun container instead of a live provider
  tunnel so local parity tests remain reproducible.
- VM profiles hand local networking and firewall behavior to the VM runtime
  harness so QEMU port forwarding stays reliable during tests.
- Production still uses the real secret-backed integrations and real Gluetun VPN
  configuration.
- If QEMU host dependency errors appear, ensure your local Nix installation is
  healthy and rerun build.

## Staged testing framework

Use the staged framework to avoid hangs and isolate failures quickly:

```bash
just media-vm-test smoke
just media-vm-test-stage smoke routes
just media-vm-test-diag smoke
```

Detailed stage and artifact documentation:

- `docs/media-server-vm-testing.md`
