{ pkgs, ... }:
{
  services.libinput = {
    enable = true;

    mouse = {
      accelProfile = "flat";
      naturalScrolling = false;
    };
  };
}
