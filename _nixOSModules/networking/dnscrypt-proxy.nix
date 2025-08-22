{
  moduleName ? "custom",
}:
{ config, lib, ... }:
let
  inherit (lib) types;
  cfg = config.networking.${moduleName}.dnscrypt-proxy;
in
{
  options.networking.${moduleName}.dnscrypt-proxy = {
    enable = lib.mkEnableOption "Enable DNS configuration. If no DNS provider is selected, then dnscrypt-proxy will filter the dns servers.";
    unbound = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Enable Unbound.";
      };
      port = lib.mkOption {
        type = types.int;
        default = 5335;
        description = "Port for Unbound.";
      };
    };
    ipv4-interface = lib.mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "IPv4 interface for dnscrypt-proxy.";
    };
    ipv6-interface = lib.mkOption {
      type = types.str;
      default = "::1";
      description = "IPv6 interface for dnscrypt-proxy.";
    };
    port = lib.mkOption {
      type = types.int;
      default = 53;
      description = "Port for dnscrypt-proxy.";
    };
    servers = {
      cloudflare = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Use only Cloudflare DNS.";
      };
    };
  };

  config =
    let
      add-port =
        interface: sep:
        builtins.concatStringsSep sep [
          interface
          (builtins.toString cfg.port)
        ];

      ipv4-listen-addr = add-port cfg.ipv4-interface ":";
      ipv6-listen-addr = add-port "[${cfg.ipv6-interface}]" ":";

      ipv4-forward-addr = add-port cfg.ipv4-interface "@";
      ipv6-forward-addr = add-port cfg.ipv6-interface "@";

      det-ipv4-6 = ipv4: ipv6: [ ipv4 ] ++ (lib.optionals config.networking.enableIPv6 [ ipv6 ]);

      nameservers = det-ipv4-6 cfg.ipv4-interface cfg.ipv6-interface;
      listen_addresses = det-ipv4-6 ipv4-listen-addr ipv6-listen-addr;
      forward-addr = det-ipv4-6 ipv4-forward-addr ipv6-forward-addr;
      access-control = det-ipv4-6 "${cfg.ipv4-interface} allow" "${cfg.ipv6-interface} allow";
    in
    lib.mkMerge [
      # DNS with dnscrypt-proxy and unbound
      {
        # Configure dnscrypt-proxy
        services.dnscrypt-proxy2 = lib.mkIf cfg.enable {
          enable = true;
          # Base settings on upstream example config (https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml)
          upstreamDefaults = true;

          # Override default settings
          settings = {
            inherit listen_addresses;
            ipv6_servers = config.networking.enableIPv6;
            block_ipv6 = !config.networking.enableIPv6;
          }
          # Only filter if specific servers are not specified
          // (lib.optionalAttrs (!cfg.servers.cloudflare) {

            # Security settings
            require_dnssec = true;
            require_nolog = true;

            # DNS Server types
            dnscrypt_servers = true;
            doh_servers = false;
            odoh_servers = false;
            require_nofilter = false; # filtered servers can be used as non-filtered servers will be used as fallbacks

            # Anonymized DNS
            anonymized_dns.skip_incompatible = true;

            # Sources for DNS resolvers and relays
            sources = {
              public-resolvers = {
                urls = [
                  "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
                  "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
                ];
                cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
                minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              };
              relays = {
                urls = [
                  "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md"
                  "https://download.dnscrypt.info/resolvers-list/v3/relays.md"
                ];
                cache_file = "/var/lib/dnscrypt-proxy2/relays.md";
                minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
              };
            };

          })
          # Set DNS providers
          # Servers from the "public-resolvers" source (see down below) can
          # be viewed here: https://dnscrypt.info/public-servers
          # NOTE: if no servers are specified, dnscrypt-proxy will filter and find servers
          // (lib.optionalAttrs cfg.servers.cloudflare {
            server_names = det-ipv4-6 "cloudflare" "cloudflare-ipv6";
          });
        };

        # Set general network settings for dnscrypt-proxy and unbound
        networking = lib.mkIf cfg.enable {
          # Set static nameservers
          networkmanager.insertNameservers = nameservers;
          inherit nameservers;

          # Open firewall for dnscrypt-proxy and unbound
          firewall = {
            allowedTCPPorts = [ cfg.port ] ++ (lib.optionals cfg.unbound.enable [ cfg.unbound.port ]);
            allowedUDPPorts = [ cfg.port ] ++ (lib.optionals cfg.unbound.enable [ cfg.unbound.port ]);
          };
        };

        # Label dnscrypt-proxy2 and unbound service as part of network.target
        systemd.services = {
          dnscrypt-proxy2 = lib.mkIf cfg.enable { partOf = [ "network.target" ]; };
          unbound = lib.mkIf cfg.unbound.enable { partOf = [ "network.target" ]; };
        };

        # Disable systemd-resolved if dnscrypt-proxy service is enabled
        services.resolved.enable = lib.mkForce (!config.services.dnscrypt-proxy2.enable);

        # Unbound
        services.unbound = lib.mkIf cfg.unbound.enable {
          enable = true;
          resolveLocalQueries = true;
          enableRootTrustAnchor = false;

          settings = {
            # Many options taken from https://docs.pi-hole.net/guides/dns/unbound/
            # Some DNScrypt-proxy options taken from https://wiki.archlinux.org/title/Dnscrypt-proxy#Unbound
            server = {
              # Set the interface and port for Unbound
              interface = nameservers;
              port = cfg.unbound.port;
              inherit access-control;

              # Set IP Support
              do-ip4 = true;
              do-ip6 = config.networking.enableIPv6;

              # Enable tcp and udp
              do-tcp = true;
              do-udp = true;

              # Set log verbosity to only errors
              verbosity = 0;

              # Perform prefetching of close to expired message cache entries
              # This only applies to domains that have been frequently queried
              prefetch = true;

              # Harden settings for DNSSEC servers
              harden-glue = true;
              harden-dnssec-stripped = true;

              # Disable caps for id as it can issues with DNSSEC
              use-caps-for-id = false;

              # Set num threads to 1 (unessecary to have more than 1 thread for a single user system)
              num-threads = 1;

              # Remove private addresses
              private-address = [
                "10.0.0.0/8"
                "172.16.0.0/12"
                "192.168.0.0/16"
                "169.254.0.0/16"
                "fd00::/8"
                "fe80::/10"
              ];

              # From https://wiki.archlinux.org/title/Dnscrypt-proxy#Unbound
              do-not-query-localhost = false;

              # Other
              prefetch-key = true;
              hide-identity = true;
              hide-version = true;
            };

            # Set the forward zone to the dnscrypt-proxy listen address
            forward-zone = [
              {
                name = ".";
                inherit forward-addr;
              }
            ];
          };
        };

        # Check that Unbound port is not the same as dnscrypt-proxy port
        assertions = [
          {
            assertion = cfg.unbound.port != cfg.port;
            message = "Unbound port cannot be the same as dnscrypt-proxy port.";
          }
        ];
      }
    ];
}
