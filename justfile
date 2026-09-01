set shell := ["/usr/bin/env", "bash", "-c"]

flake := justfile_directory()

default:
    @just --list --justfile {{ justfile() }}

# ─── Flake ────────────────────────────────────────────────────────────

# Update all flake inputs, or a single input if specified
[group('Flake')]
update input="":
    nix flake update {{ input }} --flake {{ flake }}

# Update all inputs for the standalone development flake, or a single input if specified
[group('Flake')]
dev-update input="":
    nix flake update {{ input }} --flake {{ flake }}/flake/dev/

# Update all inputs for the nix-config-framework submodule, or a single input if specified
[group('Flake')]
framework-update input="":
    nix flake update {{ input }} --flake {{ flake }}/nix-config-framework/

# Update all inputs for the nixpkgs-personal submodule, or a single input if specified
[group('Flake')]
pkgs-update input="":
    nix flake update {{ input }} --flake {{ flake }}/pkgs/

# Update every flake lockfile, local package sources, and validate the resulting root flake evaluates
[group('Flake')]
update-all:
    @just update
    @just dev-update
    @just framework-update
    @just pkgs-update
    @just update-packages
    @just check-eval

# Run flake checks
[group('Flake')]
check:
    nix flake check

# Evaluate all flake checks without building them
[group('Flake')]
check-eval:
    nix flake check --no-build

# Run flake checks while rejecting import-from-derivation (IFD)
[group('Flake')]
check-no-ifd:
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

# Pass arguments directly to the repository-pinned nix-seal CLI.
[group('Secrets')]
secret *args:
    nix run path:{{ flake }}#nix-seal -- {{ args }}

# ─── Maintenance ──────────────────────────────────────────────────────

# Format all Nix files
[group('Maintenance')]
fmt:
    nix fmt

# Install the repository's pre-commit and pre-push hooks in this clone.  Use
# the justfile directory rather than the caller's current directory so this
# also works when `just -f /path/to/justfile hooks` is invoked elsewhere.
[group('Maintenance')]
hooks:
    cd {{ flake }} && nix develop . --command true

# Verify the integrity of all store paths
[group('Maintenance')]
verify:
    nix store verify --all

# Garbage-collect old generations (pass e.g. --keep 5 or --keep-since 7d)
[group('Maintenance')]
clean *args:
    nh clean all {{ args }}

# Run updater scripts from the nixpkgs-personal submodule
[group('Maintenance')]
prepare-pkgs-branch:
    @root_branch="$(git -C {{ flake }} branch --show-current)"; \
        test -n "$root_branch" || { echo "error: the superproject must be on a branch" >&2; exit 1; }; \
        if git -C {{ flake }}/pkgs show-ref --verify --quiet "refs/heads/$root_branch"; then \
            git -C {{ flake }}/pkgs switch "$root_branch"; \
        else \
            git -C {{ flake }}/pkgs switch -c "$root_branch"; \
        fi

[group('Maintenance')]
update-packages *args: prepare-pkgs-branch
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update-packages.py --all {{ args }}

# Run updater script for one local package (e.g. ttf-ms-win11-auto)
[group('Maintenance')]
update-package package *args: prepare-pkgs-branch
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update-packages.py --package {{ package }} {{ args }}
