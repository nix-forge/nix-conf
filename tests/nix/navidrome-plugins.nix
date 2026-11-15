# Validate the archives actually exposed by the configured server package.
{ pkgs, package }:
pkgs.runCommand "configured-navidrome-plugin-bundle" {
  pluginFolder = "${package}/share/plugins";
  nativeBuildInputs = [
    pkgs.unzip
    pkgs.jq
    pkgs.gnugrep
    pkgs.coreutils
  ];
} (builtins.readFile ./scripts/check-navidrome-plugins.sh)
