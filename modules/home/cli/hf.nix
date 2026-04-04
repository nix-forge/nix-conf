{ pkgs, ... }:
{
  home.packages = [ pkgs.python3Packages.huggingface-hub ];
}
