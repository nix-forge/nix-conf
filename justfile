set shell := ["bash", "-c"]

# Let Nix use Git source filtering in this checkout. Explicit path: references
# also include ignored local files. Add new source files to Git before evaluation.
flake := justfile_directory()

# Explicit workload isolation on the desktop; nix itself remains unchanged.
# Other hosts retain their native build commands.
import "hosts/shared/local/justfile"

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
    {{ task }} nix store add-path {{ quote(flake + "/flake/dev") }}
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

# Select native compilation for matching architectures, cross compilation otherwise.
[group('Linux builds')]
linux-build target package repository='.':
    @set -euo pipefail; build_system="$(nix eval --impure --raw --expr builtins.currentSystem)"; \
        case "$build_system" in x86_64-linux|aarch64-linux) ;; *) echo 'error: Linux builds require a Linux builder; run this command on a Linux host' >&2; exit 1 ;; esac; \
        case {{ quote(target) }} in x86_64-linux|aarch64-linux) ;; *) echo 'error: unsupported Linux target' >&2; exit 1 ;; esac; \
        umask 077; \
        state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix-conf/builds"; mkdir -p "$state_dir"; \
        job_dir="$(mktemp -d "$state_dir/job.XXXXXXXX")"; \
        launcher="$(nix store add-path {{ quote(flake + "/scripts/build_linux_package.py") }})"; \
        expression="$(nix store add-path {{ quote(flake + "/scripts/build-package.nix") }})"; \
        nix-store --add-root "$job_dir/launcher" --indirect -r "$launcher" > /dev/null; \
        nix-store --add-root "$job_dir/expression" --indirect -r "$expression" > /dev/null; \
        echo "Build record: $job_dir" >&2; \
        exec {{ task }} python3 "$launcher" {{ quote(flake + "/" + repository) }} "$build_system" {{ quote(target) }} {{ quote(package) }} "$job_dir" "$expression"

[group('Linux builds')]
arm-build package repository='.':
    @just --justfile {{ quote(flake + "/justfile") }} linux-build aarch64-linux {{ quote(package) }} {{ quote(repository) }}

# Build a NixOS configuration (dry build, no activation)
[group('NixOS')]
os-build hostname *args: (guard-desktop-build-location hostname)
    {{ task }} nh os build {{ flake }} -H {{ hostname }} --show-trace --no-nom {{ args }}

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

# ─── Darwin ───────────────────────────────────────────────────────────

# Build a nix-darwin configuration (dry build, no activation)
[group('Darwin')]
[positional-arguments]
darwin-build hostname *args:
    if [[ "$(uname -s)" == Darwin ]]; then nh darwin build {{ quote(flake) }} -H "$1" --show-trace "${@:2}"; else python3 {{ quote(flake) }}/scripts/mac_source.py auto --source {{ quote(flake) }} --kind build --configuration "$1" --workload-command {{ quote(task) }} -- "${@:2}"; fi

# Build and activate a nix-darwin configuration
[group('Darwin')]
[positional-arguments]
darwin-switch hostname *args:
    if [[ "$(uname -s)" == Darwin ]]; then nh darwin switch {{ quote(flake) }} -H "$1" --show-trace "${@:2}"; else python3 {{ quote(flake) }}/scripts/mac_source.py auto --source {{ quote(flake) }} --kind deploy --configuration "$1" --workload-command {{ quote(task) }} -- "${@:2}"; fi

# Export selected working bytes and submodules as one verified immutable Mac source.
[group('Darwin')]
[positional-arguments]
mac-export receipt host="macbook" *args:
    python3 {{ quote(flake) }}/scripts/mac_source.py export --source {{ quote(flake) }} --receipt "$1" --host "$2" "${@:3}"

# Reject stale local source or remote drift before executing a native Mac command.
[group('Darwin')]
[positional-arguments]
mac-run receipt +args:
    python3 {{ quote(flake) }}/scripts/mac_source.py run --receipt "$1" -- "${@:2}"

# Evaluate all temporary-fix contracts through the verified Mac export.
[group('Darwin')]
[positional-arguments]
mac-check receipt="":
    if [[ -n "$1" ]]; then python3 {{ quote(flake) }}/scripts/mac_source.py run --receipt "$1" -- nix build --no-link --no-write-lock-file --max-jobs 2 --cores 4 '.#checks.aarch64-darwin.temporary-package-fixes'; else python3 {{ quote(flake) }}/scripts/mac_source.py auto --source {{ quote(flake) }} --kind check; fi

# Run the pinned native Mac test environment against a fresh verified export.
[group('Darwin')]
[positional-arguments]
mac-test *args:
    python3 {{ quote(flake) }}/scripts/mac_source.py auto --source {{ quote(flake) }} --kind test -- "$@"

# Run another remote Mac command, creating its verified export automatically.
[group('Darwin')]
[positional-arguments]
mac-exec +args:
    python3 {{ quote(flake) }}/scripts/mac_source.py auto --source {{ quote(flake) }} --kind command -- "$@"

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
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update_packages.py --all {{ args }}

# Run updater script for one local package (e.g. ttf-ms-win11-auto)
[group('Maintenance')]
update-package package *args: prepare-pkgs-branch
    nix develop {{ flake }}/pkgs -c python {{ flake }}/pkgs/scripts/update_packages.py --package {{ package }} {{ args }}

# Validate the full font collection; pass a browser executable for rendering tests
[group('Maintenance')]
fonts-check output="/tmp/font-check" browser="":
    nix run {{ flake }}#font-check -- {{ quote(output) }} {{ if browser == "" { "" } else { quote(browser) } }}

# Record exact-source validation or repeatable phase measurements in private storage.
[group('Checks')]
evidence *args:
    cd {{ quote(flake) }} && {{ task }} nix run .#workstation-evidence -- {{ args }}

# Keep the required validation inventory separate from observed run records.
[group('Checks')]
validation-manifest:
    cd {{ quote(flake) }} && {{ task }} nix eval --json .#validationManifest

# Build an already-instantiated derivation on a matching native remote host.
# Local preparation uses the desktop queue; remote compilation does not hold it.
[group('Packages')]
remote-realise host derivation result-root cores="8":
    python3 {{ quote(flake + "/scripts/remote_realise.py") }} {{ quote(host) }} {{ quote(derivation) }} {{ quote(result-root) }} --cores {{ quote(cores) }} --workload-command {{ quote(task) }} {{ protected_system_args }}
