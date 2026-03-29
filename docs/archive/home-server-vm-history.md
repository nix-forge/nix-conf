# Home Server VM History (Archived)

This file keeps superseded investigation notes that were removed from
`docs/home-server-vm.md` to keep the main doc current and operational.

## Historical context

During early QEMU-on-macOS bring-up, repeated instability was observed in app
routes and host-forward behavior even when core services were active.

Common historical symptoms included:

- transient `502` responses at `/` despite healthy ingress listeners,
- occasional service startup timing issues for media apps,
- vmnet backend launch constraints before helper/broker workflow matured,
- stale DHCP lease selection for guest-ip checks,
- old parity runs failing due service data-path permissions in tmpfs-backed VM
  access mode.

## Historical experiment snapshot (early 2026-03-29)

| Run | `/healthz` | `/` | Media probes | Outcome |
|---|---|---|---|---|
| baseline (`CPU=max`) | pass | fail | fail | ingress up, app path unstable |
| e1000 | pass | fail | fail | no meaningful recovery |
| writethrough | pass | fail | fail | no meaningful recovery |
| tcg | pass | fail (`502`) | fail (`502`) | ingress stable, upstreams failing |
| smoke-split | pass | fail (`502`, non-fatal) | skipped | smoke contract pass |
| parity-split | fail | n/a | n/a | parity unstable at that time |

## Historical failure themes

- guest app readiness lagged behind ingress readiness,
- vmnet setup had host privilege/tooling friction,
- check script assumptions around lease ordering caused stale guest IP picks,
- parity config had service-specific writable path issues (fixed later by
  config dir/data dir overrides).

## Current pointer

For the current validated state, active commands, and troubleshooting, use:

- `docs/home-server-vm.md`
