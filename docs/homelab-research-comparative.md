# Homelab Upstream Comparative Research

Reference clones used in this pass:

- `badele/nix-homelab` @ `4c6f122bdac6807ccb09d3234eeb781624ce5954`
- `nix-media-server/nixarr` @ `7cc521933dc6800ae81ecfc91fe36237476e4ffb`
- `kiriwalawren/nixflix` @ `0d43433a728bd6df544f6b82979d410713a8ec2c`

## Repo Findings

### `kiriwalawren/nixflix`

Strongest direct pattern source for API bootstrap/reconciliation of media stack services.

- Prowlarr API reconcile via oneshot services with create/update/delete semantics:
  - `modules/prowlarr/applications.nix`
  - `modules/prowlarr/indexers.nix`
- Jellyseerr staged setup and downstream integration services:
  - `modules/jellyseerr/setupService.nix`
  - `modules/jellyseerr/jellyfinService.nix`
  - `modules/jellyseerr/radarrService.nix`
  - `modules/jellyseerr/sonarrService.nix`
  - `modules/jellyseerr/librarySyncService.nix`
  - `modules/jellyseerr/userSettingsService.nix`
- Jellyfin libraries reconciled through API and managed state:
  - `modules/jellyfin/librariesService.nix`
- Readiness/wait pattern before mutating APIs:
  - `modules/arr-common/mkWaitForApiScript.nix`
- Test discipline uses VM tests that assert not just service status but API-level integration behavior:
  - `tests/vm-tests/full-stack.nix`
  - `tests/vm-tests/prowlarr-basic.nix`
  - `tests/vm-tests/jellyseerr-basic.nix`
  - `tests/vm-tests/nginx-integration.nix`

### `nix-media-server/nixarr`

Best source for VPN confinement and security assertions.

- Service-level VPN toggles with assertions and namespace integration:
  - `nixarr/prowlarr/default.nix`
  - `nixarr/jellyseerr/default.nix`
  - `nixarr/default.nix`
- End-to-end VPN confinement tests include route and DNS leak assertions:
  - `tests/vpn-confinement-test.nix`
- Permission and ownership validation coverage:
  - `tests/permissions-test.nix`
  - `tests/simple-test.nix`

### `badele/nix-homelab`

Most useful here as ops baseline and runbook reference.

- Monitoring stack references and host modules:
  - `machines/houston/modules/grafana.nix`
  - `machines/houston/modules/victoriametrics.nix`
- Backup process and operational runbook documentation:
  - `docs/borgbackup.md`
  - `docs/borgbackup/README.md`
- Broader system health/dashboard documentation:
  - `docs/grafana.md`
  - `docs/all-features.md`

## Adoption Matrix (Applied in this repo)

### 1) API reconciliation layer

Adopted from nixflix's service-driven API reconcile pattern and wait-before-mutate approach.

- Added host-side integration value model:
  - `configs/nixos/_shared/homelab/integration-values.nix`
- Added host-side integration orchestration module:
  - `configs/nixos/_shared/homelab/integration.nix`
- Added profile wrappers:
  - `configs/nixos/home-server/modules/host-homelab-integration.nix`
  - `configs/nixos/home-server-vm/modules/host-homelab-integration.nix`
- Added Python reconcile runtime:
  - `scripts/homelab/reconcile-stack.py`
  - `scripts/homelab/lib/api.py`
  - `scripts/homelab/lib/wait.py`

### 2) Ops baseline

Adopted from badele's monitoring/backup runbook emphasis, implemented in host shared layer.

- Monitoring:
  - `configs/nixos/_shared/homelab/ops-monitoring.nix`
- Backup:
  - `configs/nixos/_shared/homelab/ops-backup.nix`
- Alerting:
  - `configs/nixos/_shared/homelab/ops-alerting.nix`
- Logging:
  - `configs/nixos/_shared/homelab/ops-logging.nix`
- Wired through shared services composition:
  - `configs/nixos/_shared/homelab/services.nix`

### 3) VM/runtime verification hardening

Adopted from nixarr/nixflix integration-test mindset (assert timers/reconcile artifacts, not only unit status).

- Extended checker:
  - `scripts/check-home-server-vm.sh`
    - verifies integration timers enabled/active
    - verifies reconcile state marker

## Notes on Scope Boundaries

- Reusable homelab modules under `modules/nixos/homelab/*` remain unopinionated and do not own orchestration.
- API wiring and ops are implemented host-side in `configs/nixos/_shared/homelab/*` and host wrappers.
- This keeps personal/topology values in host config while retaining reusable module portability.
