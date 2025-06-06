{ pkgs, self, ... }:
{
  # Wooting Keyboard
  # hardware.wooting.enable = true;

  environment.systemPackages = [ pkgs.wootility ];
  services.udev.packages = [ self.packages.${pkgs.system}.wooting-udev-rules-80he ];
}
