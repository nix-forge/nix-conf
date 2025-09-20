{
  inputs,
  config,
  system,
  lib,
  pkgs,
  ...
}@args:
let
  darwinNixEnabled = args ? darwinConfig && args.darwinConfig.nix.enable;
in
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    nix-direnv.package = inputs.nix-direnv.packages.${system}.default.override (
      # TODO: Use nix from determinate-nix if using determinate-nix
      { } // (lib.optionalAttrs (!pkgs.stdenv.isDarwin || darwinNixEnabled) { nix = config.nix.package; })
    );
  };
}
