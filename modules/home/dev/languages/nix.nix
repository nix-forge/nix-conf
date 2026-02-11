{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nixfmt
    statix
    deadnix
  ];
}
