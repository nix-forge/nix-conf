# Homelab Production Operations Baseline

This document captures the ops baseline wired for the homelab shared profile layer.

## Enabled Components

- Monitoring: Prometheus + node exporter
  - `configs/nixos/_shared/homelab/ops-monitoring.nix`
- Alerting: local Alertmanager pipeline target
  - `configs/nixos/_shared/homelab/ops-alerting.nix`
- Logging: persistent journald with retention limits
  - `configs/nixos/_shared/homelab/ops-logging.nix`
- Backup: periodic restic snapshot timer
  - `configs/nixos/_shared/homelab/ops-backup.nix`

## Integration Automation

- Reconcile service/timer:
  - `configs/nixos/_shared/homelab/integration.nix`
  - `scripts/homelab/reconcile-stack.py`

The reconciler handles Prowlarr app/download-client wiring, Arr download clients,
Seerr upstream bindings, and optional Jellyfin library provisioning.

## Service Health Expectations

- `homelab-reconcile.timer` and `homelab-backup.timer` are enabled and active.
- Reconcile writes `/var/lib/homelab-reconcile/state.json` with `{"ok": true}` on success.
- Prometheus scrapes local node and ingress health endpoints.

## Validation Commands

- `just check`
- `just secret-check`
- `nix eval .#nixosConfigurations.home-server.config.systemd.services.homelab-reconcile`
- `nix eval .#nixosConfigurations.home-server.config.systemd.timers.homelab-reconcile`
- `nix eval .#nixosConfigurations.home-server.config.services.prometheus.enable`
- `just home-server-vm-check-parity-fast`
