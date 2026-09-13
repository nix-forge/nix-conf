{ inputs, pkgs }:
let
  fixes = import ./temporary { inherit inputs pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  release = fixes.apply "prismlauncher-release" pkgs.prismlauncher-unwrapped;
  prismUnwrapped = if isDarwin then fixes.apply "prismlauncher-darwin-tests" release else release;
  deploy = inputs.deploy-rs.packages.${system}.default;
  hyprlandPackages = inputs.hyprland.packages.${system};
  swiftPackages = pkgs.swiftPackages // {
    swift = fixes.apply "swift-wrapper-hardening" pkgs.swiftPackages.swift;
  };
in
{
  prismlauncher = pkgs.prismlauncher.override { prismlauncher-unwrapped = prismUnwrapped; };
  claude-code =
    if isDarwin then fixes.apply "claude-code-sandbox" pkgs.claude-code else pkgs.claude-code;
  deploy-rs = if isDarwin then fixes.apply "deploy-rs-darwin-tests" deploy else deploy;
}
// pkgs.lib.optionalAttrs isDarwin {
  # swiftPackages is a recursive attribute set, not an overridable scope.
  # Explicit consumers keep SwiftPM and the compiler on their existing pin.
  inherit swiftPackages;
  inherit (swiftPackages) swift;
  ocr-capture = pkgs.ocr-capture.override { inherit swiftPackages; };
  finder-favorites = (pkgs.finder-favorites.override { inherit swiftPackages; }).overrideAttrs {
    SWIFT_EXEC = "${swiftPackages.swift}/bin/swiftc";
  };
  vorssaint = pkgs.vorssaint.override { inherit (swiftPackages) swift; };
  actual-server = fixes.apply "actual-server-case" pkgs.actual-server;
  nh = pkgs.nh.override { nh-unwrapped = fixes.apply "nh-darwin-home" pkgs.nh-unwrapped; };
}
// pkgs.lib.optionalAttrs isLinux {
  wrapFirefox = fixes.apply "zen-wrapper-copy" pkgs.wrapFirefox;
  # Keep the dependency repair local to the selected Virt Manager package.
  virt-manager = pkgs.virt-manager.override {
    gtksourceview4 = fixes.apply "gtksourceview-xvfb" pkgs.gtksourceview4;
  };
  vscode = fixes.apply "vscode-oniguruma-layout" pkgs.vscode;
  hyprshell = fixes.apply "hyprshell-modifiers" pkgs.hyprshell;
  hypridle = fixes.apply "hypridle-condition-inhibitors" pkgs.hypridle;
  # Retain the selected Hyprland dependency set for the native lock UI variant.
  hyprlock-personal = pkgs.hyprlock-personal.override {
    hyprlock = inputs.hyprlock.packages.${system}.hyprlock;
  };
  hyprland = fixes.apply "hyprland-subsurface" hyprlandPackages.hyprland;
  xdg-desktop-portal-hyprland = fixes.apply "hyprland-portal" hyprlandPackages.xdg-desktop-portal-hyprland;
  grimblast-region = import ./permanent/grimblast-region.nix pkgs.grimblast;
}
