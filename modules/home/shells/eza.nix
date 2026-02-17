{ config, ... }:
{
  programs.eza = {
    enable = true;

    colors = "auto";
    git = config.programs.git.enable;
    icons = "auto";
  };

  home.shellAliases = {
    l = "eza -a";
    ll = "eza -l";
    lt = "eza --tree --long";
  };
}
