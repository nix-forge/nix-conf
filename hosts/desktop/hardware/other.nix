{ pkgs, self, ... }:
{
  services.udev.packages = [
    self.packages.${pkgs.system}.openocd-esp32-udev-rules
  ];
}
