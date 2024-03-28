{pkgs, ...}: {
  services.xserver = {
    enable = true;

    programs.dconf.enable = true;

    displayManager.gdm = {
      enable = true;
      wayland = true;
    };

    desktopManager.gnome.enable = true;
    environment.gnome.excludePackages = [];
  };
}
