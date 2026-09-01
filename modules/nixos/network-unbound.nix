{ config, lib, ... }:
let
  cfg = config.networking.unboundResolver;
  loopbackAddresses = [ "127.0.0.1" ] ++ lib.optional config.networking.enableIPv6 "::1";
  loopbackAccess = [
    "127.0.0.0/8 allow"
  ]
  ++ lib.optional config.networking.enableIPv6 "::1/128 allow";
  resolverAddresses = [
    "127.0.0.1:${toString cfg.port}"
  ]
  ++ lib.optional config.networking.enableIPv6 "[::1]:${toString cfg.port}";
in
{
  options.networking.unboundResolver = {
    enable = lib.mkEnableOption ''
      a loopback-only Unbound validating DNS resolver as an alternative to the
      local DNS-blocking resolver path
    '';

    mode = lib.mkOption {
      type = lib.types.enum [
        "recursive"
        "forward-tls"
      ];
      default = "recursive";
      description = ''
        How Unbound reaches the DNS hierarchy. `recursive` is independent of a
        public resolver but sends ordinary DNS to root and authoritative
        servers. `forward-tls` authenticates transport to the host-local list
        of DNS-over-TLS forwarders.
      '';
    };

    forwarders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "9.9.9.9@853#dns.quad9.net" ];
      description = ''
        Authenticated DNS-over-TLS forwarders for `mode = "forward-tls"`.
        Each entry must include an IP address, port, and certificate name in
        Unbound's `IP@port#hostname` syntax. Provider choice is host-local.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5336;
      description = ''
        Loopback listener port. Keep this distinct from systemd-resolved's
        port 53 and any local filtering resolver during a tested migration.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.resolved.enable;
        message = "networking.unboundResolver requires systemd-resolved as the local NSS stub.";
      }
      {
        assertion = !(lib.attrByPath [ "networking" "dnsBlocker" "enable" ] false config);
        message = "networking.unboundResolver is an alternative resolver owner; disable networking.dnsBlocker before enabling it to avoid duplicate caches and DNSSEC policies.";
      }
      {
        assertion = cfg.mode != "forward-tls" || cfg.forwarders != [ ];
        message = "networking.unboundResolver.forward-tls mode requires host-local authenticated forwarders.";
      }
      {
        assertion = config.services.resolved.settings.Resolve.DNSSEC == false;
        message = "networking.unboundResolver performs DNSSEC validation itself; disable systemd-resolved DNSSEC to avoid duplicate validation.";
      }
    ];

    services.unbound = {
      enable = true;
      # systemd-resolved remains the sole port-53 stub and keeps resolvectl/NSS
      # behaviour intact. Unbound is intentionally private behind it.
      resolveLocalQueries = false;
      enableRootTrustAnchor = true;
      checkconf = true;

      settings = {
        server = {
          interface = loopbackAddresses;
          inherit (cfg) port;
          access-control = loopbackAccess;

          # DNSSEC validation is fail-closed. These settings harden a normal
          # recursive resolver without enabling strict QNAME minimisation or
          # stale-answer serving, both of which have material compatibility or
          # correctness trade-offs on a desktop.
          "module-config" = "validator iterator";
          "qname-minimisation" = true;
          "qname-minimisation-strict" = false;
          "aggressive-nsec" = true;
          "harden-glue" = true;
          "harden-dnssec-stripped" = true;
          "harden-below-nxdomain" = true;
          "harden-algo-downgrade" = true;
          "minimal-responses" = true;
          "deny-any" = true;
          "edns-buffer-size" = 1232;
          "private-address" = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "fc00::/7"
            "fe80::/10"
          ];

          # Do not retain browsing metadata in daemon logs or expose a remote
          # control interface. The NixOS service already confines Unbound;
          # the capability override below is safe because this module never
          # binds a privileged port.
          verbosity = 0;
          "log-queries" = false;
          "log-replies" = false;
          "log-servfail" = false;
          "hide-identity" = true;
          "hide-version" = true;
        };
      }
      // lib.optionalAttrs (cfg.mode == "forward-tls") {
        "forward-zone" = [
          {
            name = ".";
            "forward-tls-upstream" = true;
            "forward-first" = false;
            "forward-addr" = cfg.forwarders;
          }
        ];
      };
    };

    services.resolved.settings.Resolve = {
      DNS = resolverAddresses;
      Domains = [ "~." ];
      FallbackDNS = [ ];
      DNSSEC = false;
      DNSOverTLS = false;
    };

    systemd.services.unbound.serviceConfig = {
      AmbientCapabilities = lib.mkForce [ ];
      CapabilityBoundingSet = lib.mkForce [ ];
      UMask = "0077";
    };
  };
}
