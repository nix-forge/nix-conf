{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  pairingPolicy = pkgs.writers.writePython3 "disable-bluetooth-pairing" {
    libraries = [ pkgs.python3Packages.dbus-next ];
    # Match Ruff's line wrapping and leading binary operators.
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/disable_bluetooth_pairing.py;
  disableBluetoothPairing = writeBashTemplate {
    name = "disable-bluetooth-pairing";
    src = ./scripts/disable-bluetooth-pairing.sh;
    replacements = {
      bash = lib.getExe pkgs.bash;
      policyScript = pairingPolicy;
    };
  };
in
{
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
    };

    input.General = {
      # Classic HID devices must already be bonded. Leave LE's automatic
      # security upgrade enabled for compatibility with modern peripherals.
      ClassicBondedOnly = true;
      LEAutoSecurity = true;
    };
  };

  # Blueman provides a regular-user pairing and device-management flow.
  services.blueman.enable = lib.mkDefault config.hardware.bluetooth.enable;

  # BlueZ defaults every powered adapter to Pairable=true.  AlwaysPairable
  # only controls whether pairing is accepted without an agent, so enforce the
  # stricter default after bluetoothd has registered every adapter.  This does
  # not disable the radio or discovery, and a user can still deliberately turn
  # pairing on through Blueman or bluetoothctl when adding a device.
  systemd.services.bluetooth-disable-pairing = lib.mkIf config.hardware.bluetooth.enable {
    description = "Disable unsolicited Bluetooth pairing";
    wantedBy = [ "bluetooth.target" ];
    requires = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];

    serviceConfig = {
      Type = "oneshot";
      # BlueZ may publish its D-Bus adapter well after bluetoothd starts while
      # USB firmware initializes. The helper blocks on InterfacesAdded.
      ExecStart = "${disableBluetoothPairing} --timeout 45";
      TimeoutStartSec = "50s";
      Restart = "on-failure";
      RestartSec = "10s";
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };
  };

  # PipeWire/WirePlumber owns Bluetooth audio. Preserve its adaptive codec
  # selection and headset-profile handling, but prevent private audio from
  # unexpectedly falling back to speakers when Bluetooth playback disappears.
  services.pipewire.wireplumber.extraConfig."10-bluetooth-policy" =
    lib.mkIf
      (
        config.hardware.bluetooth.enable
        && config.services.pipewire.enable
        && config.services.pipewire.wireplumber.enable
      )
      {
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = true;
          "bluetooth.profile-preference" = "quality";
          "bluetooth.use-persistent-storage" = true;
          "device.routes.mute-on-bluetooth-playback-removed" = true;
        };
      };
}
