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

# Build media-server VM smoke/parity artifact
[group('NixOS')]
media-vm-build profile="parity":
    nix build path:{{ flake }}#nixosConfigurations.media-server-vm-{{ profile }}.config.system.build.vm -L

# Run media-server VM smoke/parity artifact
[group('NixOS')]
media-vm-run profile="parity" *args:
    just media-vm-build {{ profile }}
    ./result/bin/run-media-server-vm-{{ profile }}-vm {{ args }}

# Remove VM disk image and symlink result for a clean rerun
[group('NixOS')]
media-vm-reset profile="parity":
    rm -f ./media-server-vm-{{ profile }}.qcow2
    rm -f ./result

# Host-side smoke checks against forwarded VM ports
[group('NixOS')]
media-vm-check profile="smoke":
    {{ flake }}/scripts/media-vm-test.sh {{ profile }} all

# Run full staged VM test framework
[group('NixOS')]
media-vm-test profile="smoke":
    {{ flake }}/scripts/media-vm-test.sh {{ profile }} all

# Run a single stage from the VM test framework
[group('NixOS')]
media-vm-test-stage profile="smoke" stage="routes":
    {{ flake }}/scripts/media-vm-test.sh {{ profile }} {{ stage }}

# Collect diagnostics from latest VM test artifact directory
[group('NixOS')]
media-vm-test-diag profile="smoke":
    bash -eu -c 'dir=$(ls -1dt ./.artifacts/media-vm-tests/*-{{ profile }} 2>/dev/null | head -n1 || true); if [ -z "$dir" ]; then echo "No artifacts found for profile {{ profile }}"; exit 1; fi; echo "Artifact: $dir"; [ -f "$dir/summary.txt" ] && cat "$dir/summary.txt"; [ -d "$dir/diag" ] && find "$dir/diag" -maxdepth 1 -type f -print'

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
secret-edit secret_id:
    nix run path:{{ flake }}#secretctl -- edit {{ secret_id }}

# Create/replace a secret from plaintext file
[group('Secrets')]
secret-encrypt secret_id source:
    nix run path:{{ flake }}#secretctl -- encrypt {{ secret_id }} --from {{ source }}

# Re-encrypt one secret or all secrets from config metadata
[group('Secrets')]
secret-reencrypt *args:
    nix run path:{{ flake }}#secretctl -- reencrypt {{ args }}

# Copy and re-encrypt media VM secrets from parity to smoke
[group('Secrets')]
media-vm-secret-sync source="media-server-vm-parity" dest="media-server-vm-smoke":
    {{ flake }}/scripts/media-vm-secret-sync.sh {{ source }} {{ dest }}

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
