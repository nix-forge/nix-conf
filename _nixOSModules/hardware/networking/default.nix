{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  cfg = config.networking;
in
{
  imports = [
    ./dnscrypt-proxy.nix
    ./tcp-optimizations.nix
    ./firewall
  ];

  options.networking = {
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

  config =

    lib.mkMerge [
      # Host ID
      {
        # Generate HostID from Hostname
        # NOTE: This hashes the hostname with sha256 then takes the first 8 characters as a substring.
        networking.hostId = lib.mkIf cfg.generateHostId (
          builtins.substring 0 8 (builtins.hashString "sha256" cfg.hostName)
        );
      }

      # IWD Configuration
      {
        networking.wireless.iwd = lib.mkIf (cfg.networkmanager.wifi.backend == "iwd") {
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
            Network.EnableIPv6 = cfg.enableIPv6;
            IPv6.Enabled = cfg.enableIPv6;

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
        networking.networkmanager = lib.mkIf cfg.networkmanager.enable {
          dns = lib.mkIf (config.services.dnscrypt-proxy2.enable || config.systemd.network.enable) (
            if config.services.dnscrypt-proxy2.enable then "none" else "systemd-resolved"
          );
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
        # If using NetworkManager disable systemd-networkd-wait-online if NetworkManager wait-online is enabled
        systemd.network.wait-online.enable = lib.mkIf cfg.networkmanager.enable (
          lib.mkForce (!config.systemd.services.NetworkManager-wait-online.enable)
        );
        # systemd = {
        #   network.wait-online.enable = lib.mkForce false;
        #   services.NetworkManager-wait-online.enable = lib.mkForce false;
        # };
      }

      # Enforce IPv6 Disable at Kernel Level
      { boot.kernelParams = lib.mkIf (!cfg.enableIPv6) [ "ipv6.disable=1" ]; }

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

      # Warning for using DHCP
      {
        warnings = (
          lib.optionals cfg.useDHCP [ "It is recommended to use systemd-networkd instead of DHCP." ]
        );
      }
    ];
}
