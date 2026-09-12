set shell := ["/usr/bin/env", "bash", "-c"]

# Let Nix use Git source filtering in this checkout. Explicit path: references
# also include ignored local files. Add new source files to Git before evaluation.
flake := justfile_directory()

# Explicit workload isolation on the desktop; nix itself remains unchanged.
# Other hosts retain their native build commands.
task := if os() == "linux" { if `hostname -s` == "desktop" { "workstation-task" } else { "" } } else { "" }

default:
    @just --list --justfile {{ justfile() }}

# Run root Python behavior tests with pinned dependencies; pass pytest selectors.
[group('Checks')]
test-python *args:
    cd {{ quote(flake) }} && {{ task }} nix develop {{ quote(flake) }}#tests --command python3 -m pytest {{ args }}

# Exercise CI orchestration against disposable Git repositories and a real Nix daemon.
[group('Checks')]
test-ci *args:
    cd {{ quote(flake) }} && {{ task }} nix develop {{ quote(flake) }}#tests --command python3 -m pytest -m nix_daemon tests/ci {{ args }}

# Build all generated-file checks for this platform, including rejection tests.
[group('Checks')]
generated-checks:
    {{ task }} nix build --no-link --option allow-import-from-derivation false "{{ flake }}#checks.$(nix eval --impure --raw --expr builtins.currentSystem).generated-artifacts"

# Install/boot disposable disks and exercise backup restoration and policy checks.
[group('Checks')]
desktop-storage-check:
    {{ task }} nix build --no-link "{{ flake }}#checks.x86_64-linux.desktop-storage-contracts" "{{ flake }}#checks.x86_64-linux.python-tests" "{{ flake }}#checks.x86_64-linux.desktop-storage-install"

# Build the proposed encrypted TPM-PIN system without changing deployment flags or activating it.
[group('NixOS')]
desktop-storage-build: (guard-desktop-build-location "desktop")
    NIX_CONF_STORAGE_BUILD_ROOT={{ quote(flake) }} {{ task }} nix build --no-link --impure --expr 'let f = builtins.getFlake (builtins.getEnv "NIX_CONF_STORAGE_BUILD_ROOT"); in (f.nixosConfigurations.desktop.extendModules { modules = [ ({ lib, ... }: { hardware.storage.encryptedRoot = { enable = true; unlockMethod = "tpm-pin"; }; security.secureBootLanzaboote = { enable = lib.mkForce true; measuredBoot.enable = lib.mkForce true; }; }) ]; }).config.system.build.toplevel'

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
    {{ task }} nix flake check

# Evaluate all flake checks without building them
[group('Flake')]
check-eval:
    {{ task }} nix flake check --no-build

# Run flake checks while rejecting import-from-derivation (IFD)
[group('Flake')]
check-no-ifd:
    {{ task }} nix flake check --no-allow-import-from-derivation

# Review temporary package fix guards on every supported platform
[group('Flake')]
temporary-fixes-check:
    {{ task }} nix build --no-link "{{ flake }}#checks.$(nix eval --impure --raw --expr builtins.currentSystem).temporary-package-fixes"

# Show flake outputs
[group('Flake')]
show:
    {{ task }} nix flake show

# ─── NixOS ────────────────────────────────────────────────────────────

[private]
guard-desktop-build-location hostname:
    @actual_hostname="$(hostname -s)"; \
        if [[ "{{ hostname }}" == "desktop" && "$actual_hostname" != "desktop" ]]; then \
            echo "error: refusing to build NixOS host '{{ hostname }}' on '$actual_hostname'" >&2; \
            echo "hint: use 'just desktop-build' or 'just desktop-deploy' from another machine" >&2; \
            exit 1; \
        fi

# Build a NixOS configuration (dry build, no activation)
[group('NixOS')]
os-build hostname *args: (guard-desktop-build-location hostname)
    {{ task }} nh os build {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a NixOS configuration, and make it the boot default
[group('NixOS')]
os-switch hostname *args: (guard-desktop-build-location hostname)
    {{ task }} nh os switch {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build a NixOS configuration and make it the boot default (no activation)
[group('NixOS')]
os-boot hostname *args: (guard-desktop-build-location hostname)
    {{ task }} nh os boot {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a NixOS configuration (without adding to boot menu)
[group('NixOS')]
os-test hostname *args: (guard-desktop-build-location hostname)
    {{ task }} nh os test {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# From another host, remotely build the desktop and show the activation diff
[group('NixOS')]
desktop-build *args:
    deploy --remote-build --dry-activate {{ args }} {{ flake }}#desktop

# From another host, remotely build and activate the desktop
[group('NixOS')]
desktop-deploy *args:
    deploy --remote-build {{ args }} {{ flake }}#desktop

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
    {{ task }} nh home build {{ flake }} -c {{ configuration }} --show-trace {{ args }}

# Build and activate a home-manager configuration
[group('Home')]
home-switch configuration *args:
    {{ task }} nh home switch {{ flake }} -c {{ configuration }} --show-trace {{ args }}

# ─── Secrets ──────────────────────────────────────────────────────────

# Pass arguments directly to the repository-pinned nix-seal CLI.
[group('Secrets')]
secret *args:
    nix run "{{ flake }}#nix-seal" -- {{ args }}

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

# Validate the full font collection; pass a browser executable for rendering tests
[group('Maintenance')]
fonts-check output="/tmp/font-check" browser="":
    nix run {{ flake }}#font-check -- {{ quote(output) }} {{ if browser == "" { "" } else { quote(browser) } }}

# Record exact-source validation or repeatable phase measurements in private storage.
[group('Checks')]
evidence *args:
    cd {{ quote(flake) }} && {{ task }} nix run .#workstation-evidence -- {{ args }}

# Capture a native desktop build with its evaluated and realized system output.
[group('Checks')]
desktop-validation-build: (guard-desktop-build-location "desktop")
    cd {{ quote(flake) }} && {{ task }} nix run .#workstation-evidence -- run --target desktop --check full-system --phase build --installable nixosConfigurations.desktop.config.system.build.toplevel -- just os-build desktop

# Keep the required validation inventory separate from observed run records.
[group('Checks')]
validation-manifest:
    cd {{ quote(flake) }} && {{ task }} nix eval --json .#validationManifest
