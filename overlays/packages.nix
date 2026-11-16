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
    "azure-cli"
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
  nom = fixes.apply "nom-quadratic-build-plan" pkgs.nix-output-monitor;
  nh = pkgs.nh.override {
    nix-output-monitor = nom;
    nh-unwrapped =
      if isDarwin then fixes.apply "nh-darwin-home" pkgs.nh-unwrapped else pkgs.nh-unwrapped;
  };
in
{
  rea = import ../lib/rea-runtime.nix {
    inherit inputs system;
    package = pkgs.rea;
  };
  blocky = fixes.apply "blocky-multiple-dnskeys" pkgs.blocky;
  opencode = fixes.apply "opencode-dependency-hashes" pkgs.opencode;
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
  nix-output-monitor = nom;
  inherit nh;
  deploy-rs =
    if isDarwin then
      fixes.apply "deploy-rs-darwin-tests" (fixes.apply "deploy-rs-confirmation-path" deploy)
    else
      deploy;
}
// pkgs.lib.optionalAttrs isDarwin {
  handy = fixes.apply "handy-darwin-signature" pkgs.handy;
  rift = fixes.apply "rift-native-app-switch" pkgs.rift;
  aerospace = fixes.apply "darwin-application-signatures" pkgs.aerospace;
  signal-desktop = fixes.apply "darwin-application-signatures" pkgs.signal-desktop;
  zoom-us = fixes.apply "darwin-application-signatures" pkgs.zoom-us;
  prismlauncher = pkgs.prismlauncher.override {
    prismlauncher-unwrapped = fixes.apply "prismlauncher-darwin-tests" pkgs.prismlauncher-unwrapped;
  };
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
  hyprlock = fixes.apply "hyprlock-graphics-cleanup" inputs.hyprlock.packages.${system}.hyprlock;
  hyprland = fixes.apply "hyprland-subsurface-rounding" (
    fixes.apply "hyprland-subsurface" hyprlandPackages.hyprland
  );
  inherit (hyprlandPackages) xdg-desktop-portal-hyprland;
}

// upstreamSelections

// pkgs.lib.optionalAttrs (isDarwin && upstreamSelections ? linearmouse) {
  linearmouse = fixes.apply "linearmouse-apfs-streams" upstreamSelections.linearmouse;
}
