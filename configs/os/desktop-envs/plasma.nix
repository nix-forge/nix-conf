{
  services = {
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      wayland.compositor = "kwin";
    };

    desktopManager.plasma6.enable = true;
  };
}
