{ lib, config, ... }:
{
  # sounds server use RealtimeKit (rtkit) to acquire realtime priority
  security.rtkit.enable = lib.mkForce config.services.pipewire.enable;
}
