{ pkgs, ... }:
{
  home.packages = with pkgs; [
    typst
    tinymist
    typstyle
  ];
}
