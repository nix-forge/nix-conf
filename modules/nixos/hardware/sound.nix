{ config, lib, ... }: {
  # A portable PipeWire desktop baseline.  Device policy (clock rate, quantum,
  # profiles, codecs, and ALSA period settings) belongs in a host's local
  # configuration because it depends on the attached hardware and workload.
  #
  # `mkDefault` makes this feature composable: a host can deliberately choose
  # another audio server or adjust a compatibility layer without fighting a
  # `mkForce` from generic hardware configuration.
  services.pipewire = {
    enable = lib.mkDefault true;
    audio.enable = lib.mkDefault true;

    alsa = {
      enable = lib.mkDefault true;
      # Keeps legacy 32-bit games and launchers working on x86_64. NixOS only
      # installs the compatible plugins on platforms that provide them.
      support32Bit = lib.mkDefault true;
    };

    # These compatibility servers are lightweight and cover the normal Linux
    # desktop surface: PulseAudio applications, ALSA clients, and JACK-aware
    # games or audio tools. They are not separate sound daemons.
    pulse.enable = lib.mkDefault true;
    jack.enable = lib.mkDefault true;
    wireplumber.enable = lib.mkDefault true;
  };

  # PipeWire's RT module uses RTKit when the user does not have direct RT
  # rlimits. This is the least-privilege default: it avoids granting every
  # process launched by a member of the `audio` group unlimited memlock or
  # realtime priority. Hosts needing a dedicated production-audio policy can
  # opt in to narrowly scoped PAM limits locally.
  security.rtkit.enable = lib.mkDefault config.services.pipewire.enable;

  # PipeWire owns the PulseAudio protocol socket. Do not implicitly enable the
  # legacy PulseAudio daemon when a host intentionally disables PipeWire; that
  # is an explicit host policy decision.
  services.pulseaudio.enable = lib.mkDefault false;
}
