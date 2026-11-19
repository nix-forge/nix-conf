{ lib, pkgs, ... }: {
  home.packages = with pkgs; [
    # Rustup owns project compilers and their rustfmt, Clippy and rust-src components.
    rustup
    # Keep the standalone LSP server ahead of Rustup's rust-analyzer shim.
    (lib.hiPrio rust-analyzer)

    # Interactive checks, test execution, coverage and snapshot review.
    bacon
    cargo-nextest
    cargo-insta
    cargo-tarpaulin

    # Dependency security, licensing, cleanup and upgrades.
    cargo-audit
    cargo-deny
    cargo-machete
    cargo-outdated
    cargo-edit

    # Feature combinations, API compatibility and binary size inspection.
    cargo-hack
    cargo-semver-checks
    cargo-expand
    cargo-bloat
    cargo-flamegraph
  ];
}
