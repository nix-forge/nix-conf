{ config, lib, ... }:
{
  # While PipeWire is an objectively superior sound server to PulseAudio
  # the system should fall back to PulseAudio if (and only if) the system
  # advertises sound support, but PipeWire is disabled.
  hardware.pulseaudio.enable = lib.mkForce (!config.services.pipewire.enable);
}
