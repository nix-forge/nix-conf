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
    dnscrypt-proxy = {
      enable = lib.mkEnableOption "Enable DNS configuration. If no DNS provider is selected, then dnscrypt-proxy will filter the dns servers.";
      cloudflare = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Use Cloudflare DNS and do not use filtered and tested dns servers.";
      };
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
    # IWD Configuration
    {
      networking.wireless.iwd = lib.mkIf (cfg.networkmanager.wifi.backend == "iwd") {
        enable = true;

        settings = {
          General = {
            # Enable Network Configuration
            EnableNetworkConfiguration = true;

            # Must be set to "network" to enable Random MAC Address
            AddressRandomization = lib.mkIf cfg.randomizeMacAddress "network";

            # Set the address randomization range
            AddressRandomizationRange = lib.mkIf cfg.randomizeMacAddress "full";
          };

          Network = {
            EnableIPv6 = lib.mkIf cfg.enableIPv6 true;
          };

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
        dns = lib.mkIf (config.services.dnscrypt-proxy2.enable) "none";
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
    }

    # Host ID
    {
      # Generate HostID from Hostname
      # NOTE: This hashes the hostname with sha256 then takes the first 8 characters as a substring.
      networking.hostId = lib.mkIf cfg.generateHostId (
        builtins.substring 0 8 (builtins.hashString "sha256" cfg.hostName)
      );
    }

    # DNS
    {
      # Set static nameservers
      networking.nameservers = lib.mkIf config.services.dnscrypt-proxy2.enable (
        lib.mkForce ([ "127.0.0.1" ] ++ lib.optionals cfg.enableIPv6 [ "::1" ])
      );

      # Configure dnscrypt-proxy
      services.dnscrypt-proxy2 = lib.mkIf cfg.dnscrypt-proxy.enable {
        enable = true;
        # Base settings on upstream example config (https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml)
        upstreamDefaults = true;

        # Override default settings
        settings =
          {
            listen_addresses = [ "127.0.0.1:53" ] ++ (lib.optionals cfg.enableIPv6 [ "[::1]:53" ]);
            ipv6_servers = cfg.enableIPv6;
            block_ipv6 = !cfg.enableIPv6;

            # Security settings
            require_dnssec = true;
            require_nolog = true;
            require_nofilter = true; # Only want filtering when it is known what is being filtered

            # DNS Server types
            dnscrypt_servers = true;
            doh_servers = false;
            odoh_servers = false;

            # Anonymized DNS
            anonymized_dns.skip_incompatible = true;

          }
          # Set DNS providers
          # Servers from the "public-resolvers" source (see down below) can
          # be viewed here: https://dnscrypt.info/public-servers
          # NOTE: if no servers are specified, dnscrypt-proxy will filter and find servers
          // (lib.optionalAttrs (cfg.dnscrypt-proxy.cloudflare) {
            server_names =
              [ ]
              ++ (lib.optionals cfg.dnscrypt-proxy.cloudflare [ "cloudflare" ])
              ++ (lib.optionals (cfg.enableIPv6 && cfg.dnscrypt-proxy.cloudflare) [ "cloudflare-ipv6" ]);
          });
      };

      # Open firewall for dnscrypt-proxy
      networking.firewall = lib.mkIf config.services.dnscrypt-proxy2.enable {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };
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
