{ inputs, pkgs }:
let
  fixes = import ./temporary { inherit inputs pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  release = fixes.apply "prismlauncher-release" pkgs.prismlauncher-unwrapped;
  prismUnwrapped = if isDarwin then fixes.apply "prismlauncher-darwin-tests" release else release;
  deploy = inputs.deploy-rs.packages.${system}.default;
  hyprlandPackages = inputs.hyprland.packages.${system};
  upstreamNixCli = inputs.determinate.inputs.nix.packages.${system}.nix-cli;
  # Dependency defaults live outside Nix's component overrideScope. Obtain the
  # actual incoming dependency, including Determinate's curl customization.
  nixSentry =
    (pkgs.lib.findSingle (p: (p.pname or "") == "sentry-native")
      (throw "Determinate Nix no longer selects Sentry; review sentry-crashpad-lock")
      (throw "Determinate Nix selects multiple Sentry dependencies; review sentry-crashpad-lock")
      upstreamNixCli.buildInputs
    ).out;
  # buildInputs carries an explicitly selected output. Restore ordinary output
  # selection so Nix's C++ build gets Sentry's dev headers as well as its runtime.
  patchedNixSentry = (fixes.apply "sentry-crashpad-lock" nixSentry) // {
    outputSpecified = false;
  };
in
{
  prismlauncher = pkgs.prismlauncher.override { prismlauncher-unwrapped = prismUnwrapped; };
  claude-code =
    if isDarwin then fixes.apply "claude-code-sandbox" pkgs.claude-code else pkgs.claude-code;
  deploy-rs = if isDarwin then fixes.apply "deploy-rs-darwin-tests" deploy else deploy;
}
// pkgs.lib.optionalAttrs isDarwin {
  actual-server = fixes.apply "actual-server-case" pkgs.actual-server;
}
// pkgs.lib.optionalAttrs isLinux {
  # Determinate owns a separate Sentry package inside its component scope.
  # Keep the repair there rather than changing every Sentry consumer.
  nix = (pkgs.nix.overrideScope (_: _: { sentry-native = patchedNixSentry; })).overrideAttrs (old: {
    passthru = (old.passthru or { }) // {
      tests = (old.passthru.tests or { }) // {
        crashpad-lock = patchedNixSentry.tests.crashpad-lock;
        crashpad-lock-upstream = import ./temporary/tests/crashpad-lock.nix {
          inherit (pkgs) python3;
        } nixSentry;
      };
    };
  });
  wrapFirefox = fixes.apply "zen-wrapper-copy" pkgs.wrapFirefox;
  # Keep the dependency repair local to the selected Virt Manager package.
  virt-manager = pkgs.virt-manager.override {
    gtksourceview4 = fixes.apply "gtksourceview-xvfb" pkgs.gtksourceview4;
  };
  hyprshell = fixes.apply "hyprshell-modifiers" pkgs.hyprshell;
  hyprland = fixes.apply "hyprland-subsurface" hyprlandPackages.hyprland;
  xdg-desktop-portal-hyprland = fixes.apply "hyprland-portal" hyprlandPackages.xdg-desktop-portal-hyprland;
  grimblast-region = import ./permanent/grimblast-region.nix pkgs.grimblast;
}
