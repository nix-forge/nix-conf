{ myLib, pkgs }:
let
  inherit (pkgs) lib;
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  workspace = import ../rust-workspace.nix { inherit pkgs; };
in
writeShellApplication {
  name = "rust-workspaces";
  runtimeInputs = with pkgs; [
    age
    cargo
    cargo-audit
    cargo-deny
    cargo-machete
    cargo-nextest
    clippy
    coreutils
    diffutils
    git
    gnugrep
    jq
    openssh
    rage
    rust-analyzer
    rustc
    rustfmt
    semgrep
  ];
  runtimeEnv = {
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
    RUST_SEMGREP_CONFIG = ./rust-policy.yml;
    RUST_WORKSPACE_MEMBERS_FILE = pkgs.writeText "rust-workspace-members.json" (
      builtins.toJSON workspace.members
    );
    RUST_WORKSPACE_EXCLUSIONS = lib.concatStringsSep " " workspace.unsupportedCrates;
  };
  text = (''
    # shellcheck shell=bash
    case ''${1:-} in
    list | check | audit | analyzer | test) ;;
    *)
      printf 'Usage: rust-workspaces {list|check|audit|analyzer [--verbose|--diagnostics]|test}\n' >&2
      exit 2
      ;;
    esac
    lane=$1
    shift
    analyzer_args=(analysis-stats)
    if [[ $lane == analyzer ]]; then
      case ''${1:-} in
      --verbose)
        analyzer_args=(-v -v analysis-stats)
        shift
        ;;
      --diagnostics)
        analyzer_args=(diagnostics)
        shift
        ;;
      esac
    fi
    if (($#)); then
      printf 'Unexpected arguments to rust-workspaces %s\n' "$lane" >&2
      exit 2
    fi

    root=$(git rev-parse --show-toplevel)
    cd "$root" || exit
    root=$(pwd -P)
    scratch=$(mktemp -d)
    trap 'rm -rf -- "$scratch"' EXIT

    git submodule status --recursive >"$scratch/status"
    if grep -Eq '^[-U]' "$scratch/status"; then
      printf 'Initialize or resolve submodules before checking Rust workspaces.\n' >&2
      exit 1
    fi
    # shellcheck disable=SC2016
    git submodule foreach --quiet --recursive 'printf "%s\0" "$displaypath"' >"$scratch/submodules"
    mapfile -d ''' -t repos <"$scratch/submodules"
    declare -A workspaces=()
    sources=()

    for repo in . "''${repos[@]}"; do
      owner=$(cd "$repo" && pwd -P)
      git -C "$repo" ls-files -z --cached --others --exclude-standard -- ':(glob)**/Cargo.toml' '*.rs' |
        sort -zu >"$scratch/files"
      while IFS= read -r -d ''' file; do
        path=$repo/$file
        path=''${path#./}
        # The patched upstream age source is covered through each dependency graph.
        [[ $path != nix-seal/vendor/age/* && -f $path ]] || continue
        case $file in
        Cargo.toml | */Cargo.toml)
          manifest=$(cd "$repo" && cargo locate-project --workspace --message-format plain --manifest-path "$file")
          if [[ $manifest != "$owner/"* ]]; then
            printf '%s resolves outside its owning repository: %s\n' "$path" "$manifest" >&2
            exit 1
          fi
          workspaces[''${manifest#"$root/"}]=1
          ;;
        *.rs) sources+=("$path") ;;
        esac
      done <"$scratch/files"
    done

    if ((''${#workspaces[@]} == 0)); then
      printf 'No Cargo workspaces discovered.\n' >&2
      exit 1
    fi
    printf '%s\0' "''${!workspaces[@]}" | sort -z >"$scratch/workspaces"
    mapfile -d ''' -t manifests <"$scratch/workspaces"

    if [[ $lane == list ]]; then
      printf '%s\n' "''${manifests[@]}"
      exit
    fi

    # One failed check should still leave results for the other workspaces.
    failed=()
    run() {
      local label=$1
      shift
      printf '\n==> %s\n' "$label" >&2
      if ! "$@"; then
        failed+=("$label")
      fi
    }

    scan_sources() {
      local status=0
      SEMGREP_SETTINGS_FILE="$scratch/semgrep-settings.yml" semgrep scan \
        --config "$RUST_SEMGREP_CONFIG" --oss-only --error --strict --disable-nosem --no-git-ignore \
        --metrics=off --disable-version-check --jobs 2 --timeout 30 \
        --json --output "$scratch/semgrep.json" -- "''${sources[@]}" || status=$?
      jq -r '(.results[] | "\(.path):\(.start.line): \(.extra.message) [\(.check_id)]"), (.errors[] | .message)' \
        "$scratch/semgrep.json" || return 1
      printf '%s\0' "''${sources[@]}" | sort -z >"$scratch/expected" || return 1
      jq -jr '.paths.scanned[] | . + "\u0000"' "$scratch/semgrep.json" |
        sort -zu >"$scratch/scanned" || return 1
      if ! cmp -s "$scratch/expected" "$scratch/scanned"; then
        printf 'Semgrep omitted Rust sources:\n' >&2
        comm -z -23 "$scratch/expected" "$scratch/scanned" | tr '\0' '\n' >&2
        status=1
      fi
      return "$status"
    }

    unused_dependencies() {
      # Scan Cargo members explicitly to keep independent and vendored crates out.
      local metadata
      metadata=$(cargo metadata --locked --no-deps --format-version 1) || return 1
      if [[ $manifest == Cargo.toml ]]; then
        # Cargo also discovers members through local path dependencies.
        jq -er --slurpfile declared "$RUST_WORKSPACE_MEMBERS_FILE" '
          [.workspace_members as $members | .packages[]
           | select(.id as $id | $members | index($id)) | .manifest_path] as $actual
          | .workspace_root as $root
          | ($declared[0] | map($root + "/" + . + "/Cargo.toml")) as $expected
          | if ($actual | sort) == ($expected | sort) then true
            else error("Root Cargo members must be explicit. Undeclared: \(($actual - $expected) | join(", ")). Unused declarations: \(($expected - $actual) | join(", ")).")
            end
        ' <<<"$metadata" >/dev/null || return 1
      fi
      jq -jr '.workspace_members as $members | .packages[] | select(.id as $id | $members | index($id)) | .manifest_path | sub("/Cargo.toml$"; "") + "\u0000"' \
        <<<"$metadata" >"$scratch/members" || return 1
      local -a members
      mapfile -d ''' -t members <"$scratch/members"
      ((''${#members[@]} > 0)) || return 1
      cargo machete --skip-target-dir "''${members[@]}"
    }

    legacy_tests() {
      local normal_binary
      normal_binary=$(
        cd ../ || exit
        cargo build --package nix-seal --bin nix-seal --all-features --locked --message-format=json-render-diagnostics |
          jq -er 'select(.executable != null and .target.name == "nix-seal") | .executable'
      ) || return 1
      NIX_SEAL_NORMAL_TEST_BINARY="$normal_binary" cargo nextest run --locked --test rsa_migration
    }

    workspace_doctests() {
      local -a members tests
      cargo metadata --locked --no-deps --format-version 1 |
        jq -r --args '
          .workspace_members as $members | .packages[]
          | select(.id as $id | $members | index($id))
          | select(.name as $name | $ARGS.positional | index($name) | not)
          | select(any(.targets[]; .doctest)) | .name
        ' -- "$@" >"$scratch/doctests" || return 1
      mapfile -t members <"$scratch/doctests"
      tests=()
      local member
      for member in "''${members[@]}"; do
        tests+=(--package "$member")
      done
      if ((''${#tests[@]})); then
        cargo test --locked --all-features "''${tests[@]}" --doc --no-fail-fast
      fi
    }

    for manifest in "''${manifests[@]}"; do
      cd "$root/$(dirname -- "$manifest")" || exit
      packages=(--workspace --all-features --locked)
      exclusions=()
      if [[ $manifest == Cargo.toml ]]; then
        read -r -a exclusions <<<"$RUST_WORKSPACE_EXCLUSIONS"
        for package in "''${exclusions[@]}"; do
          packages+=(--exclude "$package")
        done
      fi
      policy=deny.toml
      if [[ $manifest == nix-seal/fuzz/Cargo.toml ]]; then
        # The fuzz crate shares nix-seal's policy with a local license exception.
        policy=../deny.toml
      fi
      case $lane in
      check)
        run "$manifest rustfmt" cargo fmt --all -- --check
        run "$manifest Clippy" cargo clippy "''${packages[@]}" --all-targets --keep-going -- -D warnings
        run "$manifest rustdoc" env RUSTDOCFLAGS="-D warnings" cargo doc "''${packages[@]}" --no-deps
        if [[ -f $policy ]]; then
          run "$manifest dependency policy" cargo deny --config "$policy" --locked --all-features check bans licenses sources
        else
          printf 'Missing cargo-deny policy for %s\n' "$manifest" >&2
          failed+=("$manifest dependency policy")
        fi
        run "$manifest unused dependencies" unused_dependencies
        ;;
      audit)
        if [[ $manifest == nix-seal/fuzz/Cargo.toml ]]; then
          run "$manifest advisories" cargo audit --file Cargo.lock --deny warnings
        else
          run "$manifest advisories" cargo deny --config "$policy" --locked --all-features check advisories
        fi
        ;;
      analyzer)
        if cargo fetch --locked; then
          run "$manifest rust-analyzer" env CARGO_NET_OFFLINE=true rust-analyzer "''${analyzer_args[@]}" .
        else
          failed+=("$manifest locked Cargo fetch")
        fi
        ;;
      test)
        case $manifest in
        nix-seal/Cargo.toml)
          # nextest lists libtest executables. The scale benchmark has its own harness.
          run "$manifest nextest" env NIX_SEAL_REQUIRE_INTEROP=1 NIX_SEAL_REQUIRE_SSHSIG_INTEROP=1 \
            cargo nextest run "''${packages[@]}" --lib --bins --tests --no-fail-fast
          run "$manifest doctests" workspace_doctests
          ;;
        nix-seal/legacy/Cargo.toml)
          run "$manifest migration tests" legacy_tests
          ;;
        # Fuzz targets use libFuzzer and have a dedicated suite.
        nix-seal/fuzz/Cargo.toml) ;;
        *)
          run "$manifest nextest" cargo nextest run "''${packages[@]}" --lib --bins --tests --no-tests=pass --no-fail-fast
          run "$manifest doctests" workspace_doctests "''${exclusions[@]}"
          ;;
        esac
        ;;
      esac
    done

    cd "$root" || exit
    if [[ $lane == check ]]; then
      jq -r '."rust-analyzer.linkedProjects"[]' .vscode/settings.json |
        sort >"$scratch/editor-workspaces"
      printf '%s\n' "''${manifests[@]}" >"$scratch/cargo-workspaces"
      run 'VS Code rust-analyzer workspace coverage' diff -u "$scratch/cargo-workspaces" "$scratch/editor-workspaces"
      run 'First-party Rust Semgrep policy' scan_sources
    fi

    if ((''${#failed[@]})); then
      printf '\nFailed checks:\n' >&2
      printf '  %s\n' "''${failed[@]}" >&2
      exit 1
    fi
  '');
}
