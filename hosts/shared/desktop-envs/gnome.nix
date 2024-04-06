{ pkgs, ... }:
{
  services.xserver = {
    enable = true;

    displayManager.gdm = {
      enable = true;
      wayland = true;
    };

    desktopManager.gnome.enable = true;
  };

  programs.dconf.enable = true;

  environment.gnome.excludePackages = [ ];
}
