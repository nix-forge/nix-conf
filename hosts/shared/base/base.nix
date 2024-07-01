{ pkgs, ... }:
{
  # set the systemVersion for the entire configuration
  system.stateVersion = "24.11";

  # enable dconf
  programs.dconf.enable = true;
  environment.systemPackages = [ pkgs.gnome.dconf-editor ];
}
