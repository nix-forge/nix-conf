# Media Server VM Testing Framework

This repository includes a staged VM testing framework for local MBP validation.

## Goals

- avoid non-deterministic hangs,
- isolate failures by layer,
- provide actionable logs for each failed stage.

## Command entrypoints

From repo root:

```bash
just media-vm-test smoke
just media-vm-test parity
```

Run one stage only:

```bash
just media-vm-test-stage smoke routes
```

Inspect latest diagnostics summary:

```bash
just media-vm-test-diag smoke
```

## Stage contract

The runner executes ordered stages and fails fast:

1. `preflight`
   - validates profile and required host ports.
2. `boot`
   - starts VM, verifies process alive, waits for boot markers in the serial
     log.
3. `host-port-bind`
   - confirms forwarded ports are listening on host.
4. `forwarding-liveness`
   - waits for the VM's internal Traefik smoke check marker in `vm.log`.
5. `guest-services`
   - waits for internal route checks for enabled core/media services.
6. `routes`
   - waits for internal arr route checks.
7. `security`
   - validates Cloudflare Access-style public route gating checks.
8. `torrent-safety`
   - validates torrent namespace confinement markers and final self-test pass marker.

## Timeouts and retries

- global timeout:
  - `smoke`: 8 minutes,
  - `parity`: 18 minutes.
- per-stage checks are bounded with `timeout` and retry windows.
- all loops are bounded; no infinite polling.
- the VM also runs an internal one-shot self-test service that emits pass/fail
  markers to the serial console for deterministic guest-side validation.

## Artifacts

Each run writes logs under:

```text
.artifacts/media-vm-tests/<timestamp>-<profile>/
```

Important files:

- `summary.txt` stage results table,
- `summary.json` machine-readable stage results,
- `vm.log` QEMU runtime log,
- `stage-*.log` command output per stage,
- `diag/*` targeted diagnostics on failure.

## Typical debugging flow

1. Run `just media-vm-test smoke`.
2. If failed, open the artifact path printed at command exit.
3. Read `summary.txt` first.
4. Read the failing `stage-<name>.log`.
5. If needed, inspect `diag/vm-log-tail.txt`, `diag/systemctl-failed.txt`,
   `diag/journal-services.txt`.

## Security and torrenting markers

When torrent and public exposure services are enabled, the VM self-test emits
extra markers that are consumed by staged checks:

- `MEDIA_VM_CHECK_*_PUBLIC_DENY_PASS` for unauthenticated public host denies.
- `MEDIA_VM_CHECK_*_PUBLIC_ALLOW_PASS` for requests carrying a Cloudflare
  Access JWT assertion header.
- `MEDIA_VM_CHECK_GLUETUN_HEALTH_PASS` for Gluetun service health.
- `MEDIA_VM_CHECK_QBITTORRENT_NETNS_MODE_PASS` for qBittorrent netns pinning
  (`--network=container:gluetun`).
- `MEDIA_VM_CHECK_QBITTORRENT_DIRECT_EXPOSED_PASS` for absence of direct
  qBittorrent publish rules.

In VM mode, the torrent stage validates the container topology and publish rules
using the VM fixture sidecar rather than a real provider tunnel. This keeps the
service graph and routing model aligned with production while avoiding flaky
live-VPN requirements during local testing.
