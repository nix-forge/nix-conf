{
  pkgs,
  self,
  system,
  ...
}:
{
  # Wooting Keyboard
  # hardware.wooting.enable = true;

  environment.systemPackages = [ pkgs.wootility ];
  services.udev.packages = [ self.packages.${system}.wooting-udev-rules-80he ];
}
