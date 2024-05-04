{ pkgs, tree, ... }:
{
  imports = [ ./touchpad-fix.nix ];

  services.libinput = {
    enable = true;

    touchpad = {
      accelProfile = "flat";
      naturalScrolling = false;
    };
  };
}
