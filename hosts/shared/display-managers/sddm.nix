{ pkgs, ... }:
{
  services = {
    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      wayland.compositor = "kwin";
      package = pkgs.kdePackages.sddm;
    };
  };
}
