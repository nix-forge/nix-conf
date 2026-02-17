{ lib, ... }:
{
  home.shellAliases = {
    l = lib.mkDefault "ls -a";
    ll = lib.mkDefault "ls -l";
  };
}
