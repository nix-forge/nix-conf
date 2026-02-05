{ pkgs, ... }:
{
  home.packages = [
    pkgs.gparted
    pkgs.exfatprogs
  ];
}
