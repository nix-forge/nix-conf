_: {
  # The current LibrePods Linux clients change Bluetooth profiles themselves
  # and prefer SBC-XQ or SBC without considering AAC. Keep them out of the
  # audio path until that behavior can be patched upstream or locally.
  programs.librepods.enable = false;

  # The user manager lingers so session services can run before a local login.
  # Start RTKit before logins are permitted. Otherwise PipeWire can start too
  # early, lose its realtime request, and keep running its data loops under
  # ordinary scheduling until restarted.
  # RTKit remains the privilege boundary; do not grant the whole audio group
  # unrestricted realtime priority or CAP_SYS_NICE.
  systemd.services.rtkit-daemon = {
    wantedBy = [ "multi-user.target" ];
    before = [ "systemd-user-sessions.service" ];
  };

  # This machine is both a desktop and a Sunshine host, so use one stable
  # 48 kHz graph rather than dynamically changing rates.  48 kHz is native to
  # the USB interface and to the common game, video, and streaming paths.
  #
  # A 512-sample quantum is 10.67 ms. It cuts wakeups by 75 percent compared
  # with the old 128-frame setup and passed the full-CPU playback test without
  # an underrun. Keep a 256-frame lower bound for latency-sensitive clients
  # and an upstream-sized 2048-frame ceiling for recovery. Do not use
  # `clock.force-quantum`: it prevents compatible JACK/production workloads
  # from selecting their own safe size and can disrupt a live graph.
  services.pipewire = {
    extraConfig = {
      pipewire."90-desktop-audio"."context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.allowed-rates" = [ 48000 ];
        "default.clock.quantum" = 512;
        "default.clock.min-quantum" = 256;
        "default.clock.max-quantum" = 2048;
      };

      # Do not globally force client or PulseAudio-compatible stream latency.
      # Their adaptive defaults preserve buffering margin under mixed load.
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

          # Leave sample format as UNKNOWN so PipeWire picks the highest format
          # supported by each UCM path.  In particular, do not blindly force
          # S24_3LE on the digital output. Let PipeWire detect batch devices and
          # size their periods, headroom, and hardware buffers automatically.
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
