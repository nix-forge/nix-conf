{ lib, ... }: {
  hardware.bluetooth = {
    enable = lib.mkDefault true;
    powerOnBoot = lib.mkDefault true;

    # SAP exposes a legacy SIM-access service that this desktop does not use.
    # Keep all ordinary input, audio, OBEX, and PAN capabilities available.
    disabledPlugins = [ "sap" ];

    settings.General = {
      # Keep BR/EDR for established audio/input devices and LE for modern
      # peripherals. BlueZ uses the adapter's actual supported transports.
      ControllerMode = "dual";
      MultiProfile = "multiple";

      # Use resolvable private addresses for LE without rejecting peers that
      # retain their identity address. This is the privacy/interoperability
      # balance recommended for a general-purpose dual-mode desktop.
      Privacy = "device";

      # Do not leave the radio open to unsolicited pairing. Blueman and
      # bluetoothctl can deliberately enable pairing when adding a device.
      AlwaysPairable = false;
      PairableTimeout = 60;

      # Require explicit local consent before a peer replaces an existing
      # Just Works bond. Keep Secure Connections available where supported;
      # do not force `only`, which would need an inventory of every legacy
      # peripheral before it could be a safe shared policy.
      JustWorksRepairing = "confirm";
      SecureConnections = "on";

      # Experimental BlueZ interfaces and kernel feature flags are unsuitable
      # as a shared desktop default.
      Experimental = false;
      Testing = false;
      KernelExperimental = false;
    };

    input.General = {
      # Classic HID devices must already be bonded. Leave LE's automatic
      # security upgrade enabled for compatibility with modern peripherals.
      ClassicBondedOnly = true;
      LEAutoSecurity = true;
    };
  };

  # Blueman provides a regular-user pairing and device-management flow.
  services.blueman.enable = lib.mkDefault true;

  # PipeWire/WirePlumber owns Bluetooth audio. Preserve its adaptive codec
  # selection and headset-profile handling, but prevent private audio from
  # unexpectedly falling back to speakers when Bluetooth playback disappears.
  services.pipewire.wireplumber.extraConfig."10-bluetooth-policy" = {
    "wireplumber.settings" = {
      "bluetooth.autoswitch-to-headset-profile" = true;
      "bluetooth.profile-preference" = "quality";
      "bluetooth.use-persistent-storage" = true;
      "device.routes.mute-on-bluetooth-playback-removed" = true;
    };
  };
}
