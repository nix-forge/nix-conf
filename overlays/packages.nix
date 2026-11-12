{ inputs, pkgs }:
let
  fixes = import ./temporary { inherit inputs pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  upstreamApps = import inputs.nixpkgs-apps {
    inherit system;
    config.allowUnfree = true;
  };
  upstreamNames = [
    "aurral"
    "bookorbit"
    "cadcraft"
    "deckcraft"
    "gridcraft"
    "lightcraft"
    "pdfcraft"
    "photocraft"
    "soundcraft"
    "vectorcraft"
    "wordcraft"
    "codex"
    "chatgpt"
    "feishin"
    "stirling-pdf"
    "linearmouse"
  ];
  upstreamSelections = pkgs.lib.filterAttrs (
    _: package: pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform package
  ) (pkgs.lib.genAttrs upstreamNames (name: upstreamApps.${name}));
  officialT3code = (import inputs.nixpkgs-t3code { inherit system; }).t3code;
  deploy = inputs.deploy-rs.packages.${system}.default;
  hyprlandPackages = inputs.hyprland.packages.${system};
  swift = fixes.apply "swift-clang-hardening" pkgs.swift;
  nom = fixes.apply "nom-named-activities" (
    fixes.apply "nom-quadratic-build-plan" pkgs.nix-output-monitor
  );
  nh = pkgs.nh.override {
    nix-output-monitor = nom;
    nh-unwrapped =
      if isDarwin then fixes.apply "nh-darwin-home" pkgs.nh-unwrapped else pkgs.nh-unwrapped;
  };
in
{
  azure-cli = fixes.apply "azure-cli-invoke" pkgs.azure-cli;
  blocky = fixes.apply "blocky-multiple-dnskeys" pkgs.blocky;
  nu_scripts = fixes.apply "nu-scripts-pytest-lists" pkgs.nu_scripts;
  # Keep the official CLI/server; select the signed vendor GUI only on ARM Darwin.
  t3code =
    if system == "aarch64-darwin" then
      fixes.apply "t3code-darwin-vendor-gui" (
        officialT3code.override {
          t3code-unwrapped = fixes.apply "t3code-darwin-workspace-shims" officialT3code.unwrapped;
        }
      )
    else
      officialT3code;
  actual-server = fixes.apply "actual-redact-secret-log" pkgs.actual-server;
  nix-output-monitor = nom;
  inherit nh;
  deploy-rs =
    if isDarwin then
      fixes.apply "deploy-rs-darwin-tests" (fixes.apply "deploy-rs-confirmation-path" deploy)
    else
      deploy;
}
// pkgs.lib.optionalAttrs isDarwin {
  rift = fixes.apply "rift-native-app-switch" pkgs.rift;
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
  hyprshell = fixes.apply "hyprshell-workspace-identity" (
    fixes.apply "hyprshell-workspace-schema" (fixes.apply "hyprshell-modifiers" pkgs.hyprshell)
  );
  hypridle = fixes.apply "hypridle-condition-inhibitors" pkgs.hypridle;
  # Retain the selected Hyprland dependency set for the native lock UI variant.
  hyprlock-personal = pkgs.hyprlock-personal.override {
    hyprlock = inputs.hyprlock.packages.${system}.hyprlock;
  };
  hyprland = fixes.apply "hyprland-subsurface-rounding" (
    fixes.apply "hyprland-subsurface" hyprlandPackages.hyprland
  );
  inherit (hyprlandPackages) xdg-desktop-portal-hyprland;
}

// upstreamSelections

// pkgs.lib.optionalAttrs (isDarwin && upstreamSelections ? linearmouse) {
  linearmouse = fixes.apply "linearmouse-apfs-streams" upstreamSelections.linearmouse;
}
