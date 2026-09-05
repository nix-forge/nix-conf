_: {
  # The current LibrePods Linux clients change Bluetooth profiles themselves
  # and prefer SBC-XQ or SBC without considering AAC. Keep them out of the
  # audio path until that behavior can be patched upstream or locally.
  programs.librepods.enable = false;

  # This machine is both a desktop and a Sunshine host, so use one stable
  # 48 kHz graph rather than dynamically changing rates.  48 kHz is native to
  # the USB interface and to the common game, video, and streaming paths.
  #
  # A 128-sample quantum is 2.67 ms.  It is a substantial reduction from the
  # upstream 1024-sample (21.3 ms) desktop default while leaving enough
  # scheduling headroom for a graphical workstation.  Do not use
  # `clock.force-quantum`: it prevents compatible JACK/production workloads
  # from selecting their own safe size and can disrupt a live graph.
  services.pipewire = {
    extraConfig = {
      pipewire."90-desktop-low-latency"."context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [ 48000 ];
        "default.clock.quantum" = 128;
        "default.clock.min-quantum" = 128;
        # Preserve a compatibility escape hatch for clients that cannot run
        # reliably at 128 frames; this is not a forced graph size.
        "default.clock.max-quantum" = 1024;
      };

      # Native PipeWire and ALSA clients receive the same low-latency request.
      # This is a suggestion, not a lock, so an application may still request
      # a larger buffer when it genuinely needs one.
      client."90-desktop-low-latency"."stream.properties" = {
        "node.latency" = "128/48000";
      };

      # Most desktop applications use the PulseAudio compatibility server.
      # Set both playback and capture defaults to two 128-frame periods rather
      # than merely lowering the minimum, which otherwise leaves unconfigured
      # clients at the upstream ~20 ms / 2 s defaults.
      pipewire-pulse."90-desktop-low-latency"."pulse.properties" = {
        "pulse.min.req" = "128/48000";
        "pulse.default.req" = "128/48000";
        "pulse.min.frag" = "128/48000";
        "pulse.default.frag" = "128/48000";
        "pulse.default.tlength" = "256/48000";
        "pulse.min.quantum" = "128/48000";
      };

      pipewire-pulse."90-desktop-low-latency"."stream.properties" = {
        "node.latency" = "128/48000";
      };
    };

    wireplumber.extraConfig."90-usb-audio-low-latency"."monitor.alsa.rules" = [
      {
        # The USB card has separate UCM nodes for its S/PDIF, analogue, and
        # capture paths.  Match only those nodes, not HDMI or Bluetooth.
        matches = [
          { "node.name" = "~alsa_output.usb-Generic_USB_Audio-00.*"; }
          { "node.name" = "~alsa_input.usb-Generic_USB_Audio-00.*"; }
        ];
        actions.update-props = {
          "audio.rate" = 48000;

          # USB ALSA devices are normally batch devices.  At 128 frames this
          # yields a 64-frame batch delay and more frequent, safe wake-ups.
          # Three periods give the device a small underrun margin without
          # reinstating the large default buffer.  The device defaults already
          # use zero headroom, stated explicitly here for reviewability.
          "api.alsa.period-size" = 128;
          "api.alsa.period-num" = 3;
          "api.alsa.headroom" = 0;

          # Leave sample format as UNKNOWN so PipeWire picks the highest format
          # supported by each UCM path.  In particular, do not blindly force
          # S24_3LE on the digital output.  Also retain the ALSA batch and
          # timer scheduling safeguards until an actual loopback/xrun test
          # proves this particular USB interface benefits from overriding them.
        };
      }
    ];

    wireplumber.extraConfig."91-airpods-pro" = {
      "wireplumber.settings" = {
        # Opening the AirPods microphone switches ordinary Bluetooth audio to
        # lower-quality HFP. Keep AAC playback stable and use the desktop's
        # separate USB microphone; HFP remains available for manual selection.
        "bluetooth.autoswitch-to-headset-profile" = false;
      };

      "monitor.bluez.properties" = {
        # AirPods media controls depend on an AVRCP player being registered.
        # WirePlumber supplies the player, so do not run mpris-proxy as well.
        "bluez5.dummy-avrcp-player" = true;
      };

      "monitor.bluez.rules" = [
        {
          matches = [
            {
              # Scope the recovery policy to this paired AirPods Pro 2 card.
              "device.name" = "bluez_card.6C_12_70_1A_3A_43";
            }
          ];
          actions.update-props = {
            # Attach the playback and microphone transports if BlueZ has only
            # established the base Bluetooth link. The autoswitch setting
            # above keeps A2DP selected unless HFP is chosen manually.
            "bluez5.auto-connect" = [
              "a2dp_sink"
              "hfp_hf"
            ];

            # AirPods Pro 2 uses AAC for its best standard Bluetooth playback
            # path. PipeWire defines mode 5 as its highest AAC VBR quality.
            "bluez5.a2dp.aac.bitratemode" = 5;
          };
        }
      ];
    };
  };
}
