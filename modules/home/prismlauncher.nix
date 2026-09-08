{ lib, pkgs, ... }:
let
  stableVersion = "11.1.0";
  # Use the upstream package unchanged once nixpkgs reaches this release.
  prismLauncher =
    if lib.versionOlder pkgs.prismlauncher.version stableVersion then
      pkgs.prismlauncher.override {
        prismlauncher-unwrapped = pkgs.prismlauncher-unwrapped.overrideAttrs {
          version = stableVersion;
          src = pkgs.fetchFromGitHub {
            owner = "PrismLauncher";
            repo = "PrismLauncher";
            tag = stableVersion;
            hash = "sha256-bt2ofUj4PXWKNmdACMpXtbVWdNz1aBOUTrPnOsM7NCA=";
          };
        };
      }
    else
      pkgs.prismlauncher;
in
{
  home.packages = [ prismLauncher ];
}
