{
  inputs,
  pkgs ? null,
  lib ? pkgs.lib,
}:
let
  # Explicit registration keeps helper files from becoming active fixes.
  files = {
    actual-server-case = ./actual-server-case.nix;
    audiomuseai-plugin-loopback-host = ./audiomuseai-plugin-loopback-host.nix;
    audiomuseai-plugin-release = ./audiomuseai-plugin-release.nix;
    claude-code-sandbox = ./claude-code-sandbox.nix;
    deploy-rs-darwin-tests = ./deploy-rs-darwin-tests.nix;
    determinate-darwin-tests = ./determinate-darwin-tests.nix;
    determinate-sentry-module = ./determinate-sentry-module.nix;
    gtksourceview-xvfb = ./gtksourceview-xvfb.nix;
    hypridle-condition-inhibitors = ./hypridle-condition-inhibitors.nix;
    navidrome-release = ./navidrome-release.nix;
    nom-quadratic-build-plan = ./nom-quadratic-build-plan.nix;
    hyprland-portal = ./hyprland-portal.nix;
    hyprland-subsurface = ./hyprland-subsurface.nix;
    hyprshell-modifiers = ./hyprshell-modifiers.nix;
    nh-darwin-home = ./nh-darwin-home.nix;
    prismlauncher-darwin-tests = ./prismlauncher-darwin-tests.nix;
    prismlauncher-release = ./prismlauncher-release.nix;
    sentry-crashpad-lock = ./sentry-crashpad-lock.nix;
    stylix-nvf = ./stylix-nvf.nix;
    swift-wrapper-hardening = ./swift-wrapper-hardening.nix;
    vscode-oniguruma-layout = ./vscode-oniguruma-layout.nix;
    zen-wrapper-copy = ./zen-wrapper-copy.nix;
  };
  fixes = lib.mapAttrs (name: file: (import file { inherit pkgs lib; }) // { inherit name; }) files;
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
    in
    if appliesTo fix value then fix.apply (guard fix (revision fix) value) else value;

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
