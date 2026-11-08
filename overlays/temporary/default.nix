{
  inputs,
  pkgs ? null,
  lib ? pkgs.lib,
}:
let
  # Explicit registration keeps helper files from becoming active fixes.
  files = {
    azure-cli-invoke = ./azure-cli-invoke.nix;
    blocky-multiple-dnskeys = ./blocky-multiple-dnskeys.nix;
    codex-managed-app = ./codex-managed-app.nix;
    home-manager-protected-apps = ./home-manager-protected-apps.nix;
    home-manager-app-management-consent = ./home-manager-app-management-consent.nix;
    darwin-app-management-consent = ./darwin-app-management-consent.nix;
    darwin-application-signatures = ./darwin-application-signatures.nix;
    nixf-flake-builtins = ./nixf-flake-builtins.nix;
    nvidia-bin-patchelf = ./nvidia-bin-patchelf.nix;
    jellyfin-caption-defaults = ./jellyfin-caption-defaults.nix;
    prowlarr-torrentdownload = ./prowlarr-torrentdownload.nix;
    rift-native-app-switch = ./rift-native-app-switch.nix;
    microsocks-credential-files = ./microsocks-credential-files.nix;
    actual-redact-secret-log = ./actual-redact-secret-log.nix;
    deploy-rs-confirmation-path = ./deploy-rs-confirmation-path.nix;
    deploy-rs-darwin-tests = ./deploy-rs-darwin-tests.nix;
    determinate-darwin-tests = ./determinate-darwin-tests.nix;
    determinate-libgit2-trailing-slash = ./determinate-libgit2-trailing-slash.nix;
    determinate-libgit2-module = ./determinate-libgit2-module.nix;
    ghostty-bash-prompt = ./ghostty-bash-prompt.nix;
    gtksourceview-xvfb = ./gtksourceview-xvfb.nix;
    hypridle-condition-inhibitors = ./hypridle-condition-inhibitors.nix;
    nixos-anywhere-ssh-host-check = ./nixos-anywhere-ssh-host-check.nix;
    nom-quadratic-build-plan = ./nom-quadratic-build-plan.nix;
    nom-named-activities = ./nom-named-activities.nix;
    hyprland-subsurface = ./hyprland-subsurface.nix;
    hyprland-subsurface-rounding = ./hyprland-subsurface-rounding.nix;
    hyprshell-modifiers = ./hyprshell-modifiers.nix;
    hyprshell-workspace-schema = ./hyprshell-workspace-schema.nix;
    hyprshell-workspace-identity = ./hyprshell-workspace-identity.nix;
    nh-darwin-home = ./nh-darwin-home.nix;
    nu-scripts-pytest-lists = ./nu-scripts-pytest-lists.nix;
    prismlauncher-darwin-tests = ./prismlauncher-darwin-tests.nix;
    stirling-embedpdf-font-fallback = ./stirling-embedpdf-font-fallback.nix;
    stylix-gtk-flatpak-polarity = ./stylix-gtk-flatpak-polarity.nix;
    stylix-nvf = ./stylix-nvf.nix;
    stylix-rofi = ./stylix-rofi.nix;
    swift-clang-hardening = ./swift-clang-hardening.nix;
    t3code-darwin-vendor-gui = ./t3code-darwin-vendor-gui.nix;
    t3code-darwin-workspace-shims = ./t3code-darwin-workspace-shims.nix;
    zen-wrapper-copy = ./zen-wrapper-copy.nix;
  };
  fixes = lib.mapAttrs (
    name: file: (import file { inherit inputs pkgs lib; }) // { inherit name; }
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
