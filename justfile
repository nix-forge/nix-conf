set shell := ["/usr/bin/env", "bash", "-c"]

flake := justfile_directory()

default:
    @just --list --justfile {{ justfile() }}

# ─── Flake ────────────────────────────────────────────────────────────

# Update all flake inputs, or a single input if specified
[group('Flake')]
update input="":
    nix flake update {{ input }} --flake {{ flake }}

[group('Flake')]
os-update input="":
    nix flake update {{ input }} --flake {{ flake }}/flake/nixos/

[group('Flake')]
darwin-update input="":
    nix flake update {{ input }} --flake {{ flake }}/flake/darwin/

[group('Flake')]
update-all:
    @just update
    @just os-update
    @just darwin-update

# Run flake checks
[group('Flake')]
check:
    nix flake check --no-allow-import-from-derivation

# Show flake outputs
[group('Flake')]
show:
    nix flake show

# ─── NixOS ────────────────────────────────────────────────────────────

# Build a NixOS configuration (dry build, no activation)
[group('NixOS')]
os-build hostname *args:
    nh os build {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a NixOS configuration, and make it the boot default
[group('NixOS')]
os-switch hostname *args:
    nh os switch {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build a NixOS configuration and make it the boot default (no activation)
[group('NixOS')]
os-boot hostname *args:
    nh os boot {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a NixOS configuration (without adding to boot menu)
[group('NixOS')]
os-test hostname *args:
    nh os test {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build NixOS VM launcher for a host
[group('NixOS')]
os-vm hostname:
    nix build path:{{ flake }}#nixosConfigurations.{{ hostname }}.config.system.build.vm

# Build NixOS VM with qemu helper scripts
[group('NixOS')]
os-vm-with-bootloader hostname:
    nix build path:{{ flake }}#nixosConfigurations.{{ hostname }}.config.system.build.vmWithBootLoader

# Run the home-server VM on macOS using host-native QEMU tools
[group('NixOS')]
home-server-vm-run-macos:
    {{ flake }}/scripts/run-home-server-vm-macos.sh

# Run the home-server VM on macOS using vfkit with NAT networking
[group('NixOS')]
home-server-vm-run-macos-vfkit:
    HOME_SERVER_VM_NET_MODE=nat {{ flake }}/scripts/run-home-server-vm-macos-vfkit.sh

# Run the home-server VM on macOS using vfkit vmnet shared mode
[group('NixOS')]
home-server-vm-run-macos-vfkit-vmnet-shared:
    HOME_SERVER_VM_NET_MODE=vmnet-shared {{ flake }}/scripts/run-home-server-vm-macos-vfkit.sh

# Run the home-server VM on macOS using vfkit vmnet shared mode (force helper)
[group('NixOS')]
home-server-vm-run-macos-vfkit-vmnet-shared-helper:
    HOME_SERVER_VM_NET_MODE=vmnet-shared HOME_SERVER_VM_VMNET_PROVIDER=helper {{ flake }}/scripts/run-home-server-vm-macos-vfkit.sh

# Run the home-server VM on macOS using vfkit vmnet host mode
[group('NixOS')]
home-server-vm-run-macos-vfkit-vmnet-host:
    HOME_SERVER_VM_NET_MODE=vmnet-host {{ flake }}/scripts/run-home-server-vm-macos-vfkit.sh

# Build the home-server VM and run local smoke checks against a running instance
[group('NixOS')]
home-server-vm-check:
    nix build path:{{ flake }}#nixosConfigurations.home-server-vm.config.system.build.vm
    @echo "Start the VM in another terminal with: just home-server-vm-run-macos"
    HOME_SERVER_VM_PROFILE=smoke HOME_SERVER_VM_ENABLE_MEDIA_PROBES=0 {{ flake }}/scripts/check-home-server-vm.sh

# Build the home-server VM and run parity checks against a running instance
[group('NixOS')]
home-server-vm-check-parity:
    nix build path:{{ flake }}#nixosConfigurations.home-server-vm.config.system.build.vm
    @echo "Start the VM in another terminal with: just home-server-vm-run-macos"
    HOME_SERVER_VM_PROFILE=parity HOME_SERVER_VM_ENABLE_MEDIA_PROBES=1 {{ flake }}/scripts/check-home-server-vm.sh

# Build the home-server VM and run checks against a vfkit-running instance
[group('NixOS')]
home-server-vm-check-vfkit:
    nix build path:{{ flake }}#nixosConfigurations.home-server-vm.config.system.build.vm
    @echo "Start the VM in another terminal with: just home-server-vm-run-macos-vfkit"
    HOME_SERVER_VM_CONNECT_MODE=guest-ip HOME_SERVER_VM_SSH_PORT=22 HOME_SERVER_VM_INGRESS_PORT=443 HOME_SERVER_VM_PROFILE=smoke HOME_SERVER_VM_ENABLE_MEDIA_PROBES=0 {{ flake }}/scripts/check-home-server-vm.sh

# Build the home-server VM and run parity checks against a vfkit-running instance
[group('NixOS')]
home-server-vm-check-vfkit-parity:
    nix build path:{{ flake }}#nixosConfigurations.home-server-vm.config.system.build.vm
    @echo "Start the VM in another terminal with: just home-server-vm-run-macos-vfkit"
    HOME_SERVER_VM_CONNECT_MODE=guest-ip HOME_SERVER_VM_SSH_PORT=22 HOME_SERVER_VM_INGRESS_PORT=443 HOME_SERVER_VM_PROFILE=parity HOME_SERVER_VM_ENABLE_MEDIA_PROBES=1 {{ flake }}/scripts/check-home-server-vm.sh

# Run fast smoke checks for a running home-server VM with short timeouts/retries
[group('NixOS')]
home-server-vm-check-fast:
    HOME_SERVER_VM_WAIT_SECONDS=45 \
    HOME_SERVER_VM_CORE_WAIT_SECONDS=90 \
    HOME_SERVER_VM_PROFILE=smoke \
    HOME_SERVER_VM_ENABLE_MEDIA_PROBES=0 \
    HOME_SERVER_VM_INGRESS_PROBE_PATH=/healthz \
    HOME_SERVER_VM_HTTP_CONNECT_TIMEOUT=1 \
    HOME_SERVER_VM_HTTP_MAX_TIME=3 \
    HOME_SERVER_VM_HTTP_RETRIES=3 \
    HOME_SERVER_VM_HTTP_RETRY_DELAY=2 \
    HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=0 \
    just home-server-vm-check

# Run fast parity checks for a running VM with short timeout/retry defaults
[group('NixOS')]
home-server-vm-check-parity-fast:
    HOME_SERVER_VM_WAIT_SECONDS=45 \
    HOME_SERVER_VM_CORE_WAIT_SECONDS=90 \
    HOME_SERVER_VM_PROFILE=parity \
    HOME_SERVER_VM_ENABLE_MEDIA_PROBES=1 \
    HOME_SERVER_VM_INGRESS_PROBE_PATH=/healthz \
    HOME_SERVER_VM_HTTP_CONNECT_TIMEOUT=1 \
    HOME_SERVER_VM_HTTP_MAX_TIME=3 \
    HOME_SERVER_VM_HTTP_RETRIES=3 \
    HOME_SERVER_VM_HTTP_RETRY_DELAY=2 \
    HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=0 \
    just home-server-vm-check-parity

# Run fast smoke checks against a running vfkit VM
[group('NixOS')]
home-server-vm-check-vfkit-fast:
    HOME_SERVER_VM_WAIT_SECONDS=45 \
    HOME_SERVER_VM_CORE_WAIT_SECONDS=90 \
    HOME_SERVER_VM_CONNECT_MODE=guest-ip \
    HOME_SERVER_VM_SSH_PORT=22 \
    HOME_SERVER_VM_INGRESS_PORT=443 \
    HOME_SERVER_VM_PROFILE=smoke \
    HOME_SERVER_VM_ENABLE_MEDIA_PROBES=0 \
    HOME_SERVER_VM_INGRESS_PROBE_PATH=/healthz \
    HOME_SERVER_VM_HTTP_CONNECT_TIMEOUT=1 \
    HOME_SERVER_VM_HTTP_MAX_TIME=3 \
    HOME_SERVER_VM_HTTP_RETRIES=3 \
    HOME_SERVER_VM_HTTP_RETRY_DELAY=2 \
    HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=0 \
    just home-server-vm-check-vfkit

# Run fast parity checks against a running vfkit VM
[group('NixOS')]
home-server-vm-check-vfkit-parity-fast:
    HOME_SERVER_VM_WAIT_SECONDS=45 \
    HOME_SERVER_VM_CORE_WAIT_SECONDS=90 \
    HOME_SERVER_VM_CONNECT_MODE=guest-ip \
    HOME_SERVER_VM_SSH_PORT=22 \
    HOME_SERVER_VM_INGRESS_PORT=443 \
    HOME_SERVER_VM_PROFILE=parity \
    HOME_SERVER_VM_ENABLE_MEDIA_PROBES=1 \
    HOME_SERVER_VM_INGRESS_PROBE_PATH=/healthz \
    HOME_SERVER_VM_HTTP_CONNECT_TIMEOUT=1 \
    HOME_SERVER_VM_HTTP_MAX_TIME=3 \
    HOME_SERVER_VM_HTTP_RETRIES=3 \
    HOME_SERVER_VM_HTTP_RETRY_DELAY=2 \
    HOME_SERVER_VM_HOMEPAGE_PROBE_REQUIRED=0 \
    just home-server-vm-check-vfkit-parity

# ─── Darwin ───────────────────────────────────────────────────────────

# Build a nix-darwin configuration (dry build, no activation)
[group('Darwin')]
darwin-build hostname *args:
    nh darwin build {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a nix-darwin configuration
[group('Darwin')]
darwin-switch hostname *args:
    nh darwin switch {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# ─── Home Manager ─────────────────────────────────────────────────────

# Build a home-manager configuration (dry build, no activation)
[group('Home')]
home-build configuration *args:
    nh home build {{ flake }} -c {{ configuration }} --show-trace {{ args }}

# Build and activate a home-manager configuration
[group('Home')]
home-switch configuration *args:
    nh home switch {{ flake }} -c {{ configuration }} --show-trace {{ args }}

# ─── Deploy ───────────────────────────────────────────────────────────

# Validate deploy-rs definitions via flake checks
[group('Deploy')]
deploy-check:
    nix flake check --no-allow-import-from-derivation

# Run shellcheck across repo shell scripts
[group('Dev')]
lint-shell:
    shellcheck --shell=bash --severity=style --external-sources scripts/*.sh

# Format repo shell scripts with shfmt
[group('Dev')]
fmt-shell:
    shfmt -i 2 -ci -bn -sr -kp -w scripts/*.sh

# Deploy all configured profiles with deploy-rs
[group('Deploy')]
deploy *args:
    nix run github:serokell/deploy-rs -- {{ flake }} {{ args }}

# Provision a new machine using nixos-anywhere
[group('Deploy')]
nixos-anywhere host target *args:
    nix run github:nix-community/nixos-anywhere -- --flake {{ flake }}#{{ host }} {{ target }} {{ args }}

# ─── Secrets ──────────────────────────────────────────────────────────

# Validate config-driven secret metadata and recipients
[group('Secrets')]
secret-lint:
    nix run path:{{ flake }}#secretctl -- lint

# Validate secret metadata and ensure ciphertext files exist
[group('Secrets')]
secret-check:
    nix run path:{{ flake }}#secretctl -- check

# Show resolved recipients for a secret ID
[group('Secrets')]
secret-recipients secret_id:
    nix run path:{{ flake }}#secretctl -- recipients {{ secret_id }}

# View a secret by ID
[group('Secrets')]
secret-view secret_id:
    nix run path:{{ flake }}#secretctl -- view {{ secret_id }}

# Edit a secret by ID via $EDITOR
[group('Secrets')]
secret-edit secret_id *args:
    nix run path:{{ flake }}#secretctl -- edit {{ secret_id }} {{ args }}

# Create a new secret by ID via $EDITOR (fails if it already exists)
[group('Secrets')]
secret-create secret_id *args:
    nix run path:{{ flake }}#secretctl -- create {{ secret_id }} {{ args }}

# Create/replace a secret from plaintext file (bootstraps missing IDs)
[group('Secrets')]
secret-encrypt secret_id source:
    nix run path:{{ flake }}#secretctl -- encrypt {{ secret_id }} --from {{ source }}

# Re-encrypt one secret or all secrets from config metadata
[group('Secrets')]
secret-reencrypt *args:
    nix run path:{{ flake }}#secretctl -- reencrypt {{ args }}

# ─── Maintenance ──────────────────────────────────────────────────────

# Format all Nix files
[group('Maintenance')]
fmt:
    nix fmt

# Verify the integrity of all store paths
[group('Maintenance')]
verify:
    nix store verify --all

# Garbage-collect old generations (pass e.g. --keep 5 or --keep-since 7d)
[group('Maintenance')]
clean *args:
    nh clean all {{ args }}

# Run updater scripts for all local packages under pkgs/*/update.py
[group('Maintenance')]
update-packages *args:
    nix run nixpkgs#python3 -- {{ flake }}/scripts/update-packages.py --all {{ args }}

# Run updater script for one local package (e.g. ttf-ms-win11-auto)
[group('Maintenance')]
update-package package *args:
    nix run nixpkgs#python3 -- {{ flake }}/scripts/update-packages.py --package {{ package }} {{ args }}
