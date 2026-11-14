{ pkgs, ... }: {
  # The current LibrePods Linux clients change Bluetooth profiles themselves
  # and prefer SBC-XQ or SBC without considering AAC. Keep them out of the
  # audio path until that behavior can be patched upstream or locally.
  programs.librepods.enable = false;

  # Inspect multichannel connections on demand without a second audio server.
  environment.systemPackages = [ pkgs.qpwgraph ];

  # The mk5's separate CDC Ethernet function carries local mixer control.
  # Match the USB product, not eth0 or a port-dependent interface name. This
  # link must never supply a default route, DNS, or router advertisements.
  systemd.network.links."35-motu-control" = {
    matchConfig = {
      Driver = "cdc_ether";
      Property = [
        "ID_VENDOR_ID=07fd"
        "ID_MODEL_ID=000c"
      ];
    };
    linkConfig = {
      NamePolicy = "";
      Name = "motu-control";
    };
  };
  systemd.network.networks."35-motu-control" = {
    matchConfig = {
      Driver = "cdc_ether";
      Property = [
        "ID_VENDOR_ID=07fd"
        "ID_MODEL_ID=000c"
      ];
    };
    linkConfig.RequiredForOnline = "no";
    networkConfig = {
      DHCP = "no";
      LinkLocalAddressing = "ipv4";
      IPv6AcceptRA = false;
      LLDP = false;
      EmitLLDP = false;
      MulticastDNS = false;
      LLMNR = false;
      IPv4Forwarding = false;
      IPv6Forwarding = false;
    };
  };

  # CueMix discovery is device-to-host UDP. Permit it only on the verified
  # USB control link; no LAN listener, TCP server or trusted interface is needed.
  networking.firewall.extraInputRules = ''
    iifname "motu-control" ip saddr 169.254.0.0/16 udp dport 1280 accept comment "MOTU USB control discovery"
  '';

  # The user manager lingers so session services can run before a local login.
  # Order the user-manager template directly after RTKit: lingering managers
  # do not wait for systemd-user-sessions.service. Otherwise PipeWire can
  # start before the realtime broker is ready.
  # RTKit remains the privilege boundary; do not grant the whole audio group
  # unrestricted realtime priority or CAP_SYS_NICE.
  systemd.services.rtkit-daemon = {
    wantedBy = [ "multi-user.target" ];
    before = [ "systemd-user-sessions.service" ];
  };
  systemd.services."user@" = {
    wants = [ "rtkit-daemon.service" ];
    after = [ "rtkit-daemon.service" ];
  };

  # Use one stable 48 kHz graph rather than dynamically changing rates.  48 kHz is native to
  # the USB interface and to the common game, video, and streaming paths.
  #
  # A 512-sample quantum is 10.67 ms. It cuts wakeups by 75 percent compared
  # with the old 128-frame setup and passed the full-CPU playback test without
  # an underrun. Keep a 256-frame lower bound for latency-sensitive clients
  # and an upstream-sized 2048-frame ceiling for recovery. Do not use
  # `clock.force-quantum`: it prevents compatible JACK/production workloads
  # from selecting their own safe size and can disrupt a live graph.
  services.pipewire = {
    # ALSA UCM already splits this device into correctly mapped stereo outputs
    # and mono microphone inputs. Retain it rather than forcing Pro Audio and
    # creating duplicate loopbacks. The currently connected output is Phones.
    wireplumber.extraConfig."92-motu-desktop"."monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output.usb-MOTU_UltraLite-mk5_.*HiFi__Headphones__sink"; } ];
        actions.update-props = {
          "node.description" = "MOTU Headphones";
          "priority.session" = 1500;
        };
      }
      {
        matches = [ { "node.name" = "~alsa_input.usb-MOTU_UltraLite-mk5_.*"; } ];
        # Keep the connected webcam as the automatic call source. MOTU inputs
        # remain explicitly selectable without making loopback the default.
        actions.update-props."priority.session" = 500;
      }
      {
        matches = [ { "node.name" = "~alsa_input.usb-MOTU_UltraLite-mk5_.*HiFi__Line10__source"; } ];
        actions.update-props = {
          "node.description" = "MOTU Loopback";
          "priority.session" = 100;
        };
      }
    ];
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
