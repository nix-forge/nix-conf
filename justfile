set shell := ["bash", "-c"]

# Let Nix use Git source filtering in this checkout. Explicit path: references
# also include ignored local files. Add new source files to Git before evaluation.
flake := justfile_directory()

# Explicit workload isolation on the desktop; nix itself remains unchanged.
# Other hosts retain their native build commands.
import "hosts/shared/local/justfile"

default:
    @just --list --justfile {{ justfile() }}

# Run library function tests with the pinned Nix runner.
[group('Checks')]
test *args:
    cd {{ quote(flake) }} && nix develop --command nix-unit --flake '.#libTests' {{ args }}

# Rust formatting, Clippy, docs and static policy across initialized workspaces.
[group('Checks')]
rust-check:
    cd {{ quote(flake) }} && nix develop .#ciRust --command rust-workspaces check

# Networked advisory refresh; intentionally separate from reproducible checks.
[group('Checks')]
rust-audit:
    cd {{ quote(flake) }} && nix develop .#ciRust --command rust-workspaces audit

# Batch rust-analyzer statistics or IDE diagnostics for each Cargo workspace.
[group('Checks')]
rust-analyze flag="":
    cd {{ quote(flake) }} && nix develop .#ciRust --command rust-workspaces analyzer {{ if flag == "" { "" } else { quote(flag) } }}

# Run the native Rust suites and doctests across workspaces.
[group('Checks')]
rust-test:
    cd {{ quote(flake) }} && nix develop .#ciRust --command rust-workspaces test

# Collect LCOV from nix-seal's regular Rust tests.
[group('Checks')]
rust-coverage:
    cd {{ quote(flake) }} && nix develop .#rustAnalysis --command bash -ec 'cd nix-seal; mkdir -p target; exec env RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER= NIX_SEAL_REQUIRE_INTEROP=1 NIX_SEAL_REQUIRE_SSHSIG_INTEROP=1 cargo llvm-cov nextest --locked --workspace --all-features --lib --bins --tests --lcov --output-path target/coverage.lcov'

# Run the nix-seal core unit tests under the pinned Miri interpreter.
[group('Checks')]
rust-miri:
    cd {{ quote(flake) }} && nix develop .#rustVerification --command cargo miri test --manifest-path nix-seal/Cargo.toml --locked --package nix-seal-core --lib

# Verify nix-seal-core's bounded identifier proof.
[group('Checks')]
rust-kani:
    cd {{ quote(flake) }} && nix develop .#rustVerification --command bash -ec 'cd nix-seal; cargo metadata --locked --format-version 1 >/dev/null; exec cargo kani --package nix-seal-core --harness identifier_alphabet_matches_the_public_grammar'

# Mutate the core crate and run its unit tests on a copy of the checkout.
[group('Checks')]
rust-mutate-core output:
    @just _rust-mutate {{ quote(output) }} nix-seal-core crates/nix-seal-core/src/proofs.rs

# Mutate the policy crate and run its unit tests on a copy of the checkout.
[group('Checks')]
rust-mutate-policy output:
    @just _rust-mutate {{ quote(output) }} nix-seal-policy

_rust-mutate output package excluded_file="":
    cd {{ quote(flake) }} && nix develop .#rustAnalysis --command bash -ec 'output=$(realpath -m -- "$1"); options=(); if [[ -n $3 ]]; then options+=(--exclude "$3"); fi; cd nix-seal; exec env RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER= cargo mutants --package "$2" --test-package "$2" --gitignore=true --cargo-arg=--locked --timeout 120 --build-timeout 600 --output "$output" "${options[@]}"' bash {{ quote(output) }} {{ quote(package) }} {{ quote(excluded_file) }}

# Run a stable Cargo command with the compiler cache enabled for that command.
[group('Checks')]
[positional-arguments]
rust-cached +args:
    cd {{ quote(flake) }} && nix develop .#rustAnalysis --command env CARGO_INCREMENTAL=0 RUSTC_WRAPPER=sccache RUSTC_WORKSPACE_WRAPPER= cargo "$@"

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
    nix store add-path {{ quote(flake + "/flake/dev") }}
    # Guarded module replacements write Nix source during evaluation. Prepare
    # their store paths before flake check enters read-only evaluation.
    nix eval --no-update-lock-file --no-allow-import-from-derivation --json {{ quote(flake + "#nixosConfigurations") }} --apply 'builtins.mapAttrs (_: host: host.config.system.build.toplevel.drvPath)' >/dev/null
    nix eval --no-update-lock-file --no-allow-import-from-derivation --json {{ quote(flake + "#darwinConfigurations") }} --apply 'builtins.mapAttrs (_: host: host.system.drvPath)' >/dev/null
    nix flake check --no-build --no-update-lock-file

# Run flake checks while rejecting import-from-derivation (IFD)
[group('Flake')]
check-no-ifd:
    nix flake check --no-allow-import-from-derivation

# Show flake outputs
[group('Flake')]
show:
    nix flake show

# ─── NixOS ────────────────────────────────────────────────────────────

# Select native compilation for matching architectures, cross compilation otherwise.
[group('Linux builds')]
linux-build target package repository='.':
    @set -euo pipefail; build_system="$(nix eval --impure --raw --expr builtins.currentSystem)"; \
        case "$build_system" in x86_64-linux|aarch64-linux) ;; *) echo 'error: Linux builds require a Linux builder; run this command on a Linux host' >&2; exit 1 ;; esac; \
        case {{ quote(target) }} in x86_64-linux|aarch64-linux) ;; *) echo 'error: unsupported Linux target' >&2; exit 1 ;; esac; \
        umask 077; \
        state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix-conf/builds"; mkdir -p "$state_dir"; \
        job_dir="$(mktemp -d "$state_dir/job.XXXXXXXX")"; \
        launcher="$(nix build --out-link "$job_dir/launcher" --print-out-paths {{ quote(flake + "#build-linux-package") }})"; \
        expression="$(nix store add-path {{ quote(flake + "/scripts/build-package.nix") }})"; \
        nix-store --add-root "$job_dir/expression" --indirect -r "$expression" > /dev/null; \
        echo "Build record: $job_dir" >&2; \
        exec "$launcher/bin/build-linux-package" {{ quote(flake + "/" + repository) }} "$build_system" {{ quote(target) }} {{ quote(package) }} "$job_dir" "$expression"

[group('Linux builds')]
arm-build package repository='.':
    @just --justfile {{ quote(flake + "/justfile") }} linux-build aarch64-linux {{ quote(package) }} {{ quote(repository) }}

# Build a NixOS configuration (dry build, no activation)
[group('NixOS')]
os-build hostname *args: (guard-desktop-build-location hostname)
    nh os build {{ flake }} -H {{ hostname }} --show-trace --no-nom {{ args }}

# Build and activate a NixOS configuration, and make it the boot default
[group('NixOS')]
os-switch hostname *args: (guard-desktop-build-location hostname)
    nh os switch {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build a NixOS configuration and make it the boot default (no activation)
[group('NixOS')]
os-boot hostname *args: (guard-desktop-build-location hostname)
    nh os boot {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# Build and activate a NixOS configuration (without adding to boot menu)
[group('NixOS')]
os-test hostname *args: (guard-desktop-build-location hostname)
    nh os test {{ flake }} -H {{ hostname }} --show-trace {{ args }}

# ─── Darwin ───────────────────────────────────────────────────────────

# Build a nix-darwin configuration (dry build, no activation)
[group('Darwin')]
[positional-arguments]
darwin-build hostname *args:
    if [[ "$(uname -s)" == Darwin ]]; then nh darwin build {{ quote(flake) }} -H "$1" --show-trace "${@:2}"; else nix run {{ quote(flake + "#mac-source") }} -- auto --source {{ quote(flake) }} --kind build --configuration "$1" -- "${@:2}"; fi

# Build and activate a nix-darwin configuration
[group('Darwin')]
[positional-arguments]
darwin-switch hostname *args:
    if [[ "$(uname -s)" == Darwin ]]; then nh darwin switch {{ quote(flake) }} -H "$1" --show-trace "${@:2}"; else nix run {{ quote(flake + "#mac-source") }} -- auto --source {{ quote(flake) }} --kind deploy --configuration "$1" -- "${@:2}"; fi

# Export selected working bytes and submodules as one verified immutable Mac source.
[group('Darwin')]
[positional-arguments]
mac-export receipt host="macbook" *args:
    nix run {{ quote(flake + "#mac-source") }} -- export --source {{ quote(flake) }} --receipt "$1" --host "$2" "${@:3}"

# Reject stale local source or remote drift before executing a native Mac command.
[group('Darwin')]
[positional-arguments]
mac-run receipt +args:
    nix run {{ quote(flake + "#mac-source") }} -- run --receipt "$1" -- "${@:2}"

# Run static and library checks through the verified Mac export.
[group('Darwin')]
[positional-arguments]
mac-check receipt="":
    if [[ -n "$1" ]]; then nix run {{ quote(flake + "#mac-source") }} -- run --receipt "$1" -- nix flake check --no-write-lock-file; else nix run {{ quote(flake + "#mac-source") }} -- auto --source {{ quote(flake) }} --kind check; fi

# Run Nix library tests against a fresh verified Mac export.
[group('Darwin')]
[positional-arguments]
mac-test *args:
    nix run {{ quote(flake + "#mac-source") }} -- auto --source {{ quote(flake) }} --kind test -- "$@"

# Run another remote Mac command, creating its verified export automatically.
[group('Darwin')]
[positional-arguments]
mac-exec +args:
    nix run {{ quote(flake + "#mac-source") }} -- auto --source {{ quote(flake) }} --kind command -- "$@"

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
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update_packages.py --all {{ args }}

# Run updater script for one local package (e.g. ttf-ms-win11-auto)
[group('Maintenance')]
update-package package *args: prepare-pkgs-branch
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update_packages.py --package {{ package }} {{ args }}

# Record exact-source validation or repeatable phase measurements in private storage.
[group('Checks')]
evidence *args:
    cd {{ quote(flake) }} && nix run .#workstation-evidence -- {{ args }}

# Keep the required validation inventory separate from observed run records.
[group('Checks')]
validation-manifest:
    cd {{ quote(flake) }} && nix eval --json .#validationManifest

# Build an already-instantiated derivation on a matching native remote host.
# Prepare locally and compile on the selected remote host.
[group('Packages')]
remote-realise host derivation result-root cores="8":
    @set -euo pipefail; \
        protected_systems="$(nix eval --raw --file {{ quote(build_policy) }} \
          --apply 'policy: builtins.concatStringsSep "\n" (builtins.attrNames policy)')"; \
        protected=(); \
        while IFS= read -r system; do [[ -z "$system" ]] || protected+=(--protected-system "$system"); done <<< "$protected_systems"; \
        exec nix run {{ quote(flake + "#remote-realise") }} -- {{ quote(host) }} {{ quote(derivation) }} {{ quote(result-root) }} --cores {{ quote(cores) }} "${protected[@]}"
