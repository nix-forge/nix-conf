{pkgs, ...}: {
  services.xserver.libinput = {
    enable = true;

    mouse = {
      accelProfile = "flat";
      naturalScrolling = false;
    };
  };
}
