{ config, lib, ... }:
{
  services.pulseaudio.enable = lib.mkForce (!config.services.pipewire.enable);
}
