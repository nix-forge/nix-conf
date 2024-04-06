{
  pkgs,
  tree,
  ...
}: {
  imports = [
    ./touchpad-fix.nix
  ];

  services.xserver.libinput = {
    enable = true;

    touchpad = {
      accelProfile = "flat";
      naturalScrolling = false;
    };
  };
}
