{ pkgs, ... }: {
  # Keep the editor's Rust Analyzer extension self-contained outside a
  # `nix develop` shell as well. Dependency audit tools remain explicit
  # developer commands because refreshing their advisory databases requires
  # network access.
  home.packages = with pkgs; [
    cargo
    cargo-audit
    cargo-deny
    clippy
    rust-analyzer
    rustc
    rustfmt
  ];
}
