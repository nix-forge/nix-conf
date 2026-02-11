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

# Rekey all secrets for all configured targets
[group('Secrets')]
rekey:
    nix run path:{{ flake }}#agenix-rekey.$(nix config show system).rekey -- -a

# Update source secret recipients to the configured master identities
[group('Secrets')]
rekey-update-masterkeys:
    nix run path:{{ flake }}#agenix-rekey.$(nix config show system).update-masterkeys

# Edit (or create) a secret. If no file is given, opens fzf selector.
[group('Secrets')]
secret-edit *args:
    nix run path:{{ flake }}#agenix-rekey.$(nix config show system).edit-view -- edit {{ args }}

# View a secret. If no file is given, opens fzf selector.
[group('Secrets')]
secret-view *args:
    nix run path:{{ flake }}#agenix-rekey.$(nix config show system).edit-view -- view {{ args }}

# Create/replace a secret from an existing plaintext file.
[group('Secrets')]
secret-create input output:
    nix run path:{{ flake }}#agenix-rekey.$(nix config show system).edit-view -- edit -i {{ input }} {{ output }}

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
