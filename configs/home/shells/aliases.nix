{ lib, config, ... }:
{
  home.shellAliases =
    {
      l = "ls -a";
      ll = "ls -l";
    }
    // lib.optionalAttrs (config.programs.eza.enable) {
      l = "eza -a";
      ll = "eza -l";
      lt = "eza --tree --level=2 --long";
    };
}
