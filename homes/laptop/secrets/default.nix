{ inputs, pkgs, ... }:
# TODO: check if this already configured in NixOS
{
  imports = [ inputs.agenix.homeManagerModules.default ];

  home.packages = [
    inputs.agenix.packages.${pkgs.system}.agenix
  ];
}
