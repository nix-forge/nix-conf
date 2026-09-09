{ inputs, pkgs }:
let
  fixes = import ./temporary { inherit inputs pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux system;
  release = fixes.apply "prismlauncher-release" pkgs.prismlauncher-unwrapped;
  prismUnwrapped = if isDarwin then fixes.apply "prismlauncher-darwin-tests" release else release;
  deploy = inputs.deploy-rs.packages.${system}.default;
  hyprlandPackages = inputs.hyprland.packages.${system};
in
{
  prismlauncher = pkgs.prismlauncher.override { prismlauncher-unwrapped = prismUnwrapped; };
  claude-code =
    if isDarwin then fixes.apply "claude-code-sandbox" pkgs.claude-code else pkgs.claude-code;
  deploy-rs = if isDarwin then fixes.apply "deploy-rs-darwin-tests" deploy else deploy;
}
// pkgs.lib.optionalAttrs isDarwin {
  actual-server = fixes.apply "actual-server-case" pkgs.actual-server;
  nh = pkgs.nh.override { nh-unwrapped = fixes.apply "nh-darwin-home" pkgs.nh-unwrapped; };
}
// pkgs.lib.optionalAttrs isLinux {
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
