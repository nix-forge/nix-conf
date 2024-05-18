{ pkgs, ... }:
{
  # enable dconf
  programs.dconf.enable = true;
  environment.systemPackages = [ pkgs.gnome.dconf-editor ];
}
