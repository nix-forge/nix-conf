{ inputs, pkgs }:
let
  fixes = import ./temporary { inherit inputs pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  deploy = inputs.deploy-rs.packages.${system}.default;
  hyprlandPackages = inputs.hyprland.packages.${system};
  swift = fixes.apply "swift-clang-hardening" pkgs.swift;
  packages = {
    deploy-rs =
      if isDarwin then
        fixes.apply "deploy-rs-darwin-tests" (fixes.apply "deploy-rs-confirmation-path" deploy)
      else
        deploy;
  }
  // pkgs.lib.optionalAttrs (system == "aarch64-darwin") {
    # Keep the official CLI/server; select the signed vendor GUI only on ARM Darwin.
    t3code = fixes.apply "t3code-darwin-vendor-gui" (
      pkgs.t3code.override {
        t3code-unwrapped = fixes.apply "t3code-darwin-workspace-shims" pkgs.t3code.unwrapped;
      }
    );
  }
  // pkgs.lib.optionalAttrs isDarwin {
    azure-cli = fixes.apply "azure-cli-darwin-dependency-tests" pkgs.azure-cli;
    handy = pkgs.handy-bin;
    rift = fixes.apply "rift-keyboard-repeat-intent" pkgs.rift;
    linearmouse = fixes.apply "linearmouse-apfs-streams" pkgs.linearmouse;
    aerospace = fixes.apply "darwin-application-signatures" pkgs.aerospace;
    signal-desktop = fixes.apply "darwin-application-signatures" pkgs.signal-desktop;
    zoom-us = fixes.apply "darwin-application-signatures" pkgs.zoom-us;
    prismlauncher = pkgs.prismlauncher.override {
      prismlauncher-unwrapped = fixes.apply "prismlauncher-darwin-tests" pkgs.prismlauncher-unwrapped;
    };
    inherit swift;
    ocr-capture = pkgs.ocr-capture.override { inherit swift; };
    finder-favorites = pkgs.finder-favorites.override { inherit swift; };
    vorssaint = pkgs.vorssaint.override { inherit swift; };
  }
  // pkgs.lib.optionalAttrs isLinux {
    jellyfin-web = fixes.apply "jellyfin-caption-defaults" pkgs.jellyfin-web-personal;
    microsocks = fixes.apply "microsocks-credential-files" pkgs.microsocks;
    wrapFirefox = fixes.apply "zen-wrapper-copy" pkgs.wrapFirefox;
    # Keep the dependency repair local to the selected Virt Manager package.
    virt-manager = pkgs.virt-manager.override {
      gtksourceview4 = fixes.apply "gtksourceview-xvfb" pkgs.gtksourceview4;
    };
    hyprshell = fixes.apply "hyprshell-modifiers" pkgs.hyprshell;
    hypridle = fixes.apply "hypridle-condition-inhibitors" pkgs.hypridle;
    # Retain the selected Hyprland dependency set for the native lock UI variant.
    hyprlock = fixes.apply "hyprlock-graphics-cleanup" inputs.hyprlock.packages.${system}.hyprlock;
    hyprland = fixes.apply "hyprland-subsurface-rounding" (
      fixes.apply "hyprland-subsurface" hyprlandPackages.hyprland
    );
    inherit (hyprlandPackages) xdg-desktop-portal-hyprland;
  };
in
packages // pkgs.lib.optionalAttrs isDarwin (fixes.apply "darwin-app-metadata" (pkgs // packages))
