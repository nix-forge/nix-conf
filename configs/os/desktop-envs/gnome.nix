_: {
  services.xserver = {
    enable = true;

    desktopManager.gnome.enable = true;
  };

  programs.dconf.enable = true;

  environment.gnome.excludePackages = [ ];
}
