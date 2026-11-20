{
  inputs,
  pkgs ? null,
  lib ? pkgs.lib,
}:
let
  myLib = import ../../lib { inherit lib; };

  # Explicit registration keeps helper files from becoming active fixes.
  files = {
    darwin-app-metadata = ./darwin-app-metadata.nix;
    zen-darwin-app-metadata = ./zen-darwin-app-metadata.nix;
    helium-darwin-app-metadata = ./helium-darwin-app-metadata.nix;
    azure-cli-darwin-dependency-tests = ./azure-cli-darwin-dependency-tests.nix;
    home-manager-protected-apps = ./home-manager-protected-apps.nix;
    home-manager-app-management-consent = ./home-manager-app-management-consent.nix;
    darwin-app-management-consent = ./darwin-app-management-consent.nix;
    darwin-application-signatures = ./darwin-application-signatures.nix;
    nixf-flake-builtins = ./nixf-flake-builtins.nix;
    jellyfin-caption-defaults = ./jellyfin-caption-defaults.nix;
    prowlarr-torrentdownload = ./prowlarr-torrentdownload.nix;
    linearmouse-apfs-streams = ./linearmouse-apfs-streams.nix;
    rift-keyboard-repeat-intent = ./rift-keyboard-repeat-intent.nix;
    microsocks-credential-files = ./microsocks-credential-files.nix;
    deploy-rs-confirmation-path = ./deploy-rs-confirmation-path.nix;
    deploy-rs-darwin-tests = ./deploy-rs-darwin-tests.nix;
    determinate-darwin-sandbox-profile = ./determinate-darwin-sandbox-profile.nix;
    determinate-darwin-tests = ./determinate-darwin-tests.nix;
    determinate-libgit2-trailing-slash = ./determinate-libgit2-trailing-slash.nix;
    determinate-libgit2-module = ./determinate-libgit2-module.nix;
    gtksourceview-xvfb = ./gtksourceview-xvfb.nix;
    hypridle-condition-inhibitors = ./hypridle-condition-inhibitors.nix;
    nix-seal-emulated-sigchld-tests = ./nix-seal-emulated-sigchld-tests.nix;
    nixos-anywhere-ssh-host-check = ./nixos-anywhere-ssh-host-check.nix;
    hyprlock-graphics-cleanup = ./hyprlock-graphics-cleanup.nix;
    hyprland-subsurface = ./hyprland-subsurface.nix;
    hyprland-subsurface-rounding = ./hyprland-subsurface-rounding.nix;
    hyprshell-modifiers = ./hyprshell-modifiers.nix;
    prismlauncher-darwin-tests = ./prismlauncher-darwin-tests.nix;
    stylix-gtk-flatpak-polarity = ./stylix-gtk-flatpak-polarity.nix;
    stylix-nvf = ./stylix-nvf.nix;
    stylix-rofi = ./stylix-rofi.nix;
    swift-clang-hardening = ./swift-clang-hardening.nix;
    t3code-darwin-vendor-gui = ./t3code-darwin-vendor-gui.nix;
    t3code-darwin-workspace-shims = ./t3code-darwin-workspace-shims.nix;
    zen-wrapper-copy = ./zen-wrapper-copy.nix;
  };
  fixes = lib.mapAttrs (
    name: file:
    (import file {
      inherit
        inputs
        pkgs
        lib
        myLib
        ;
    })
    // {
      inherit name;
    }
  ) files;
  guard = import ./guard.nix { inherit lib; };
  revision = fix: (lib.getAttrFromPath fix.inputPath inputs).rev or "<unversioned input>";
  appliesTo = fix: fix.appliesTo or (_: true);
  reviewPackage = fix: lib.getAttrFromPath (lib.splitString "." fix.packageName) pkgs;
in
{
  # Callers apply a fix to its incoming package or module input.
  apply =
    name: value:
    let
      fix = fixes.${name};
      reviewed = guard fix (revision fix) value;
    in
    if appliesTo fix value then builtins.seq reviewed (fix.apply reviewed) else value;

  # Force revision review even for disabled features and other platforms.
  # Explicitly version-gated fixes retire their own guard with the patch.
  review = lib.mapAttrs (
    _: fix:
    let
      applicable = !(fix ? appliesTo) || pkgs == null || appliesTo fix (reviewPackage fix);
    in
    builtins.seq
      (if applicable then guard (fix // { affectedVersions = null; }) (revision fix) { } else null)
      {
        inherit (fix)
          reason
          upstream
          removal
          reviewedRevision
          ;
        affectedVersions = fix.affectedVersions or null;
        inherit (fix) inputPath;
        inherit applicable;
      }
  ) fixes;
}
