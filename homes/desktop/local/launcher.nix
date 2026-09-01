{ lib, ... }: {
  # Noctalia owns the only launcher in this profile. Keep Fuzzel disabled so
  # the session does not retain a second search surface.
  desktop.launcher.enable = false;
  programs.fuzzel.enable = lib.mkForce false;
}
