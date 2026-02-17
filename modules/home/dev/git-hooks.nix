{ pkgs, ... }:
{
  home = {
    packages = [ pkgs.prek ];
    shellAliases.pre-commit = "prek";
  };
}
