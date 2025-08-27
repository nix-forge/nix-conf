{ pkgs, self, system, ... }:
{
  services.udev.packages = [ self.packages.${system}.openocd-esp32-udev-rules ];
}
