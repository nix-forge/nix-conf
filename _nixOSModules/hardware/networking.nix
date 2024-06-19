{ config, lib, ... }:
let
  inherit (lib) types;
  cfg = config.networking;
in
{
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
    cloudflareDNS = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Use Cloudflare DNS.";
    };
  };

  config = {
    networking = {
      # IWD Configuration
      wireless.iwd = lib.mkIf (config.networking.networkmanager.wifi.backend == "iwd") {
        enable = true;

        settings = {
          General = {
            # Enable Network Configuration
            EnableNetworkConfiguration = true;

            # Must be set to "network" to enable Random MAC Address
            AddressRandomization = lib.mkIf cfg.randomizeMacAddress "network";
          };

          Network = {
            EnableIPv6 = lib.mkIf config.networking.enableIPv6 true;
          };

          Settings = {
            # Enable Auto Connect to WiFi
            AutoConnect = true;

            # Randomize MAC Address
            AlwaysRandomizeAddress = lib.mkIf cfg.randomizeMacAddress true;
          };
        };
      };

      # NetworkManager Random Mac Address Configuration
      networkmanager = lib.mkIf cfg.randomizeMacAddress {
        wifi.scanRandMacAddress = true;
        wifi.macAddress = "random";
        ethernet.macAddress = "random";
      };

      # Generate HostID from Hostname
      # NOTE: This hashes the hostname with sha256 then takes the first 8 characters as a substring.
      hostId = lib.mkIf cfg.generateHostId (
        builtins.substring 0 8 (builtins.hashString "sha256" config.networking.hostName)
      );
    };

    # Enabling Cloudflare DNS
    # Set static nameservers
    networking.nameservers = lib.mkForce (
      [ "127.0.0.1" ] ++ lib.optionals config.networking.enableIPv6 [ "::1" ]
    );
    # Configure dnscrypt-proxy
    services.dnscrypt-proxy2 = lib.mkIf cfg.cloudflareDNS {
      enable = true;
      # Base settings on upstream example config (https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml)
      upstreamDefaults = true;

      # Use Cloudflare DNS
      settings = {
        listen_addresses = [ "127.0.0.1:53" ] ++ lib.optionals config.networking.enableIPv6 [ "[::1]:53" ];
        ipv6_servers = config.networking.enableIPv6;
        server_names = [ "cloudflare" ] ++ lib.optionals config.networking.enableIPv6 [ "cloudflare-ipv6" ];
      };
    };
    # Open firewall for DNS
    networking.firewall = lib.mkIf cfg.cloudflareDNS {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };

    # Enforce IPv6 Disable
    # Could be related this issue: https://github.com/NixOS/nixpkgs/issues/87802
    boot.kernelParams = lib.mkIf config.networking.enableIPv6 [ "ipv6.disable=1" ];
  };
}
