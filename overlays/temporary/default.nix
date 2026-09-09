{
  inputs,
  pkgs ? null,
  lib ? pkgs.lib,
}:
let
  # Explicit registration keeps helper files from becoming active fixes.
  files = {
    actual-server-case = ./actual-server-case.nix;
    claude-code-sandbox = ./claude-code-sandbox.nix;
    deploy-rs-darwin-tests = ./deploy-rs-darwin-tests.nix;
    determinate-darwin-tests = ./determinate-darwin-tests.nix;
    gtksourceview-xvfb = ./gtksourceview-xvfb.nix;
    hyprland-portal = ./hyprland-portal.nix;
    hyprland-subsurface = ./hyprland-subsurface.nix;
    hyprshell-modifiers = ./hyprshell-modifiers.nix;
    prismlauncher-darwin-tests = ./prismlauncher-darwin-tests.nix;
    prismlauncher-release = ./prismlauncher-release.nix;
    sentry-crashpad-lock = ./sentry-crashpad-lock.nix;
    stylix-nvf = ./stylix-nvf.nix;
    zen-wrapper-copy = ./zen-wrapper-copy.nix;
  };
  fixes = lib.mapAttrs (name: file: (import file { inherit pkgs lib; }) // { inherit name; }) files;
  guard = import ./guard.nix { inherit lib; };
  revision = fix: (lib.getAttrFromPath fix.inputPath inputs).rev or "<unversioned input>";
in
{
  # Callers apply a fix to its incoming package or module input.
  apply =
    name: value:
    let
      fix = fixes.${name};
    in
    fix.apply (guard fix (revision fix) value);

  # Force every revision guard in CI, including fixes for disabled features and
  # other platforms. Package version guards are also checked at each call site.
  review = lib.mapAttrs (
    _: fix:
    builtins.seq (guard (fix // { affectedVersions = null; }) (revision fix) { }) {
      inherit (fix)
        reason
        upstream
        removal
        reviewedRevision
        ;
      affectedVersions = fix.affectedVersions or null;
      inherit (fix) inputPath;
    }
  ) fixes;
}
