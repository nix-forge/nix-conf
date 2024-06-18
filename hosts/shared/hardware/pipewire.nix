{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-gaming.nixosModules.pipewireLowLatency ];

  hardware.pulseaudio.enable = lib.mkForce false;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    wireplumber.enable = true;

    lowLatency.enable = true;
  };

  # TODO: setup xwayland bridge
  environment.systemPackages = [ pkgs.xwaylandvideobridge ];
}
