{
  myLib,
  pkgs,
  rustOverlay,
  ciRust,
}:
let
  inherit (pkgs) lib;
  rust = rustOverlay.lib.mkRustBin { } pkgs;
  miriToolchain = rust.nightly."2026-11-13".minimal.override {
    extensions = [
      "miri"
      "rust-src"
    ];
  };
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cargoMiri = writeShellApplication {
    name = "cargo-miri";
    runtimeInputs = [ miriToolchain ];
    runtimeEnv = {
      CARGO = "${miriToolchain}/bin/cargo";
      RUSTDOC = "${miriToolchain}/bin/rustdoc";
      RUSTUP_TOOLCHAIN = "${miriToolchain}";
    };
    text = ''
      unset RUSTC RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER
      exec "${miriToolchain}/bin/cargo-miri" "$@"
    '';
  };
  # Geiger forwards --locked to its embedded Cargo but omits it from the
  # external Cargo metadata command. Lock both operations.
  geigerCargo = writeShellApplication {
    name = "cargo-geiger-cargo";
    text = ''
      if [[ ''${1:-} == metadata ]]; then
        shift
        exec "${lib.getExe pkgs.cargo}" metadata --locked "$@"
      fi
      exec "${lib.getExe pkgs.cargo}" "$@"
    '';
  };
  unsafeInventory = writeShellApplication {
    name = "rust-unsafe-inventory";
    runtimeInputs = with pkgs; [
      cargo
      coreutils
      gnugrep
      jq
    ];
    text = ''
      if (($# != 1)); then
        printf 'Usage: rust-unsafe-inventory PACKAGE/Cargo.toml\n' >&2
        exit 2
      fi
      manifest=$(realpath --canonicalize-existing -- "$1")
      cd "$(dirname -- "$manifest")"
      # Avoid collecting other builds' dep-info even when Cargo has a separate build directory.
      scratch=$(mktemp -d)
      trap 'rm -rf -- "$scratch"' EXIT
      if ! CARGO="${lib.getExe geigerCargo}" \
        CARGO_TARGET_DIR="$scratch/target" CARGO_BUILD_BUILD_DIR="$scratch/build" \
        "${lib.getExe pkgs.cargo-geiger}" geiger --locked --manifest-path "$manifest" \
        --output-format Json >"$scratch/report" 2>"$scratch/log"; then
        cat "$scratch/log" >&2
        exit 1
      fi
      if grep -Eq '^(Failed to |Unrecognised Dependency Kind$)' "$scratch/log" ||
        ! jq -es '
          length == 1 and (.[0]
            | (.packages | type == "array" and length > 0)
              and (.packages_without_metrics == [])
              and (.used_but_not_scanned_files == []))
        ' "$scratch/report" >/dev/null; then
        cat "$scratch/log" >&2
        jq -r '
          (.packages_without_metrics[]? | "Package without unsafe metrics: \(.)"),
          (.used_but_not_scanned_files[]? | "Unscanned build input: \(.)")
        ' "$scratch/report" >&2 || printf 'Could not decode the unsafe inventory.\n' >&2
        printf 'cargo-geiger did not produce a complete inventory.\n' >&2
        exit 1
      fi
      cat "$scratch/report"
    '';
  };
  kani = import ./kani.nix { inherit pkgs rust; };
in
{
  rustAnalysis = pkgs.mkShell {
    inputsFrom = [ ciRust ];
    inherit (ciRust) RUSTUP_TOOLCHAIN;
    # Use the profile readers from the same LLVM release as rustc.
    LLVM_COV = "${pkgs.rustc.llvmPackages.llvm}/bin/llvm-cov";
    LLVM_PROFDATA = "${pkgs.rustc.llvmPackages.llvm}/bin/llvm-profdata";
    packages =
      (with pkgs; [
        age
        cargo-expand
        cargo-flamegraph
        cargo-geiger
        cargo-llvm-cov
        cargo-mutants
        jq
        openssh
        rage
        sccache
        unsafeInventory
      ])
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.perf ];
  };
  rustVerification = pkgs.mkShell {
    inherit (ciRust) shellHook;
    # Cargo dispatches subcommands from PATH; cargo-miri supplies its nightly.
    packages = [
      pkgs.cargo
      cargoMiri
    ]
    ++ lib.optionals (lib.meta.availableOn pkgs.stdenv.hostPlatform kani) [ kani ];
  };
}
