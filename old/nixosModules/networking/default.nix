{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  moduleName = "extras";
  cfg = config.networking.${moduleName};
in
{
  imports = [
    ./dnscrypt-proxy.nix
    ./tcp-optimizations.nix
    ./networkd.nix
    ./firewall
  ];

  options.networking.${moduleName} = {
    generateHostId = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Generate hostid from hostname.";
    };
    randomizeMacAddress = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Randomize MAC address.";
    };
    networkTools = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Enable additional network tools.";
      };
    };
  };

  config = lib.mkMerge [
    # Host ID
    {
      # Generate HostID from Hostname
      # NOTE: This hashes the hostname with sha256 then takes the first 8 characters as a substring.
      networking.hostId = lib.mkIf cfg.generateHostId (
        builtins.substring 0 8 (builtins.hashString "sha256" config.networking.hostName)
      );
    }

    # IWD Configuration
    {
      networking.wireless.iwd = lib.mkIf (config.networking.networkmanager.wifi.backend == "iwd") {
        enable = true;

        settings = {
          Scan.DisablePeriodicScan = false;

          General = {
            # Enable Network Configuration
            EnableNetworkConfiguration = true;

            # Must be set to "network" to enable Random MAC Address
            AddressRandomization = lib.mkIf cfg.randomizeMacAddress "network";

            # Set the address randomization range
            AddressRandomizationRange = lib.mkIf cfg.randomizeMacAddress "full";
          };

          # IPv6 Configuration
          Network.EnableIPv6 = config.networking.enableIPv6;
          IPv6.Enabled = config.networking.enableIPv6;

          Settings = {
            # Enable Auto Connect to WiFi
            AutoConnect = true;

            # Randomize MAC Address
            AlwaysRandomizeAddress = lib.mkIf cfg.randomizeMacAddress true;
          };
        };
      };
    }

    # Network Manager
    {
      networking.networkmanager = lib.mkIf config.networking.networkmanager.enable {
        unmanaged = [
          "interface-name:tailscale*"
          "interface-name:br-*"
          "interface-name:rndis*"
          "interface-name:docker*"
          "interface-name:virbr*"
          "interface-name:vboxnet*"
          "interface-name:waydroid*"
          "type:bridge"
        ];

        # NetworkManager Random Mac Address Configuration
        wifi.scanRandMacAddress = lib.mkIf cfg.randomizeMacAddress true;
        wifi.macAddress = lib.mkIf cfg.randomizeMacAddress "random";
        ethernet.macAddress = lib.mkIf cfg.randomizeMacAddress "random";
      };

      # Network Wait Online
      systemd.services.NetworkManager-wait-online.enable = lib.mkIf config.networking.networkmanager.enable (
        lib.mkForce false
      );
      systemd.network.wait-online.enable = lib.mkIf (!config.networking.networkmanager.enable) (
        lib.mkForce true
      );
    }

    # Enforce IPv6 Disable at Kernel Level
    { boot.kernelParams = lib.mkIf (!config.networking.enableIPv6) [ "ipv6.disable=1" ]; }

    # Additional Network Tools
    {
      boot.kernelModules = lib.mkIf cfg.networkTools.enable [ "af_packet" ];
      environment.systemPackages = lib.mkIf cfg.networkTools.enable (
        with pkgs;
        [
          mtr
          tcpdump
          traceroute
        ]
      );
    }
  ];
}
