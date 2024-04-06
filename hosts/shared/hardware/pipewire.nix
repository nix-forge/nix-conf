{ pkgs, lib, ... }:
{
  hardware.pulseaudio.enable = lib.mkForce false;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    wireplumber.enable = true;
  };

  environment.systemPackages = [ pkgs.xwaylandvideobridge ];
}
