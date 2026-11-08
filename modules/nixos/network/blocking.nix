{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.networking.dnsBlocker;
  blockyPort = cfg.port;
in
{
  options.networking.dnsBlocker = {
    enable = lib.mkEnableOption ''
      the local DNS blocking baseline
    '';

    port = lib.mkOption {
      type = lib.types.ints.between 1024 65535;
      default = 5335;
      description = "Unprivileged loopback DNS listener port, distinct from other local resolvers.";
    };

    upstreams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://dns.example.net/dns-query" ];
      description = ''
        Encrypted upstream resolvers for Blocky. Resolver choice is a
        host-local privacy and availability policy, so this shared module has
        no default provider.
      '';
    };

    bootstrapUpstreams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://1.1.1.1/dns-query" ];
      description = "Encrypted bootstrap resolvers with numeric addresses. Provider selection belongs to host-local policy.";
    };

    allowlist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "cdn.example.com" ];
      description = ''
        Domains exempted from the pinned blocking list. Keep compatibility
        exceptions host-local and as narrow as possible.
      '';
    };

    rebindingAllowlist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "router.example.net" ];
      description = ''
        Domains allowed to resolve to private addresses through a public
        upstream. This should normally remain empty.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.resolved.enable = lib.mkDefault true;
    assertions = [
      {
        assertion =
          cfg.bootstrapUpstreams != [ ]
          && lib.all (
            upstream:
            builtins.match "(https://([0-9]+[.]){3}[0-9]+(:[0-9]+)?/.*|https://[[][0-9a-fA-F:]+[]](:[0-9]+)?/.*|tcp-tls:([0-9]+[.]){3}[0-9]+(:[0-9]+)?|tcp-tls:[[][0-9a-fA-F:]+[]](:[0-9]+)?)" upstream
            != null
          ) cfg.bootstrapUpstreams;
        message = "networking.dnsBlocker requires explicit encrypted bootstrap resolvers with numeric addresses.";
      }
      {
        assertion = config.services.resolved.enable;
        message = "networking.dnsBlocker requires systemd-resolved as the local stub resolver.";
      }
      {
        assertion =
          cfg.upstreams != [ ]
          && lib.all (
            upstream: lib.hasPrefix "https://" upstream || lib.hasPrefix "tcp-tls:" upstream
          ) cfg.upstreams;
        message = "networking.dnsBlocker requires one or more host-local encrypted upstream resolvers.";
      }
      {
        assertion = config.services.resolved.settings.Resolve.DNSSEC == false;
        message = "networking.dnsBlocker delegates DNSSEC validation to Blocky; set services.resolved.settings.Resolve.DNSSEC = false in host-local configuration.";
      }
    ];

    services.blocky = {
      enable = true;
      enableConfigCheck = true;
      settings = {
        # Keep the recursive client interface local. systemd-resolved remains
        # the only system-wide stub on port 53, so no DNS listener is exposed
        # on Wi-Fi or Ethernet and applications retain normal NSS behaviour.
        ports.dns = [
          "127.0.0.1:${toString blockyPort}"
        ]
        ++ lib.optional config.networking.enableIPv6 "[::1]:${toString blockyPort}";

        # `random` sends a given query to one resolver and uses another only
        # after failure; that leaks less DNS metadata than racing providers.
        # Numeric DoH endpoints bootstrap named resolvers without sending their
        # hostnames to a plaintext DNS server or recursing through resolved.
        upstreams = {
          init.strategy = "fast";
          strategy = "random";
          timeout = "3s";
          groups.default = cfg.upstreams;
        };
        bootstrapDns = map (upstream: { inherit upstream; }) cfg.bootstrapUpstreams;

        # StevenBlack is pinned in flake.lock and read directly from the Nix
        # store. A list update is therefore reproducible and reviewable, never
        # a silent runtime policy change from a network download.
        blocking = {
          blockType = "nxDomain";
          blockTTL = "15m";
          denylists.stevenblack = [ "${inputs.stevenblack-hosts}/hosts" ];
          clientGroupsBlock.default = [ "stevenblack" ];
          loading = {
            refreshPeriod = "0s";
            strategy = "blocking";
            concurrency = 1;
          };
        }
        // lib.optionalAttrs (cfg.allowlist != [ ]) { allowlists.stevenblack = cfg.allowlist; };

        # Rebinding protection applies before cache delivery. The short
        # negative cache and bounded positive cache make a mistaken block or
        # changed DNS record recover quickly without unbounded memory growth.
        rebindingProtection = {
          enable = true;
          allowedDomains = cfg.rebindingAllowlist;
        };
        caching = {
          maxItemsCount = 20000;
          cacheTimeNegative = "5m";
          prefetching = false;
        };

        # DNS questions can be sensitive browsing metadata. Keep ordinary
        # operation quiet and avoid retaining per-domain or per-client history.
        log = {
          level = "warn";
          privacy = true;
        };
        queryLog.type = "none";

        # Blocky owns DNSSEC validation; these limits retain its built-in DoS
        # guards while avoiding a second resolver-level validation pass.
        dnssec = {
          validate = true;
          maxChainDepth = 10;
          maxUpstreamQueries = 20;
          maxNSEC3Iterations = 150;
        };
      };
    };

    services.resolved.settings.Resolve = {
      DNS = [
        "127.0.0.1:${toString blockyPort}"
      ]
      ++ lib.optional config.networking.enableIPv6 "[::1]:${toString blockyPort}";
      Domains = [ "~." ];
      FallbackDNS = [ ];
      DNSOverTLS = false;
      DNSSEC = lib.mkDefault false;
    };

    # NixOS's Blocky service is already strongly sandboxed. The listener is
    # unprivileged, so remove the generic bind-service capability and further
    # isolate temporary files, UID mappings, and process visibility.
    systemd.services.blocky.serviceConfig = {
      AmbientCapabilities = lib.mkForce "";
      CapabilityBoundingSet = lib.mkForce "";
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectProc = "invisible";
      UMask = "0077";
    };
  };
}
