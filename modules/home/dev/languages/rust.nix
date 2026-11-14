{ pkgs, ... }: {
  home.packages = with pkgs; [
    # Keep the compiler, formatter and linter on the same pinned Nixpkgs toolchain.
    cargo
    rustc
    rustfmt
    clippy
    rust-analyzer
    rustPlatform.rustLibSrc

    # Interactive checks, test execution, coverage and snapshot review.
    bacon
    cargo-nextest
    cargo-tarpaulin
    cargo-insta

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

  # rust-analyzer can navigate the standard library outside a project dev shell.
  home.sessionVariables.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
}
