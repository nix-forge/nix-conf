# Publicly trusted certificate for private media applications. DNS-01 needs no
# router forwarding; the host firewall and nginx restrict access to home LAN
# and explicitly approved WireGuard clients.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  domain = network.homelabDomain;
  siteNames = builtins.attrNames config.homelab.operations.lanHttps.sites;
  lanAddress = network.desktopTrustedAddress;
  lanSubnet = network.trustedLanCIDR;
  # Keep the host firewall and nginx in agreement. VPN clients use their
  # assigned /32 addresses so new VPN peers do not gain HTTPS access by default.
  httpsClientSources = [
    {
      label = "home LAN";
      cidr = lanSubnet;
    }
    {
      label = "iPhone via UniFi WireGuard";
      cidr = "192.168.3.2/32";
    }
    {
      label = "MacBook Pro via UniFi WireGuard";
      cidr = "192.168.3.3/32";
    }
  ];
  httpsClientCIDRs = map (source: source.cidr) httpsClientSources;
  mediaDnsUnit = "homelab-media-dns.service";
  lanReadyUnit = "homelab-lan-ready.service";
in
{
  nixSeal.secrets.homelab-cloudflare-dns-token.phase = "services";
  nixSeal.secrets.homelab-cloudflare-zone-id.phase = "services";

  security.acme = {
    acceptTerms = true;
    certs.${domain} = {
      dnsProvider = "cloudflare";
      # Certificate Transparency records only the apex and wildcard, not the
      # names of individual applications.
      extraDomainNames = [ "*.${domain}" ];
      # Keep recursive propagation checks on the local Blocky -> DoH path.
      dnsResolver = "127.0.0.1:5335";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.nixSeal.secrets.homelab-cloudflare-dns-token.path;
      group = "nginx";
      reloadServices = [ "nginx.service" ];
    };
  };

  # Lego otherwise queries authoritative name servers directly on port 53
  # during DNS-01 propagation checks. Recursive checks still run through
  # Blocky; the ACME CA performs its own independent validation.
  systemd.services."acme-order-renew-${domain}" = {
    after = [
      "blocky.service"
      mediaDnsUnit
    ];
    requires = [
      "blocky.service"
      mediaDnsUnit
    ];
    environment = {
      LEGO_DNS_PROPAGATION_DISABLE_ANS = "true";
      # Allow for recursive cache expiry and slower DNS propagation without
      # dropping a newly issued certificate request.
      CLOUDFLARE_PROPAGATION_TIMEOUT = "600";
    };
  };

  # The desktop skips the global wait-online service so a disconnected cable
  # does not hold up the desktop. These LAN listeners need the reserved wired
  # IPv4 address before they can bind.
  systemd.services.homelab-lan-ready = {
    description = "Wait for the homelab Ethernet IPv4 address";
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "infinity";
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --interface=enp13s0:routable --ipv4 --timeout=0";
    };
  };

  systemd.services.caddy = {
    after = [ lanReadyUnit ];
    requires = [ lanReadyUnit ];
  };

  systemd.services.nginx = {
    after = [ lanReadyUnit ];
    requires = [ lanReadyUnit ];
  };

  systemd.services.homelab-media-dns = {
    description = "Reconcile the private-address wildcard DNS record for HTTPS sites";
    wantedBy = [ "multi-user.target" ];
    # ACME requires this unit and starts it before ordering. A success trigger
    # here would start ACME again after every renewal preflight.
    after = [ lanReadyUnit ];
    requires = [ lanReadyUnit ];
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst = 3;
    };
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStartSec = "120s";
      ExecStart = "${pkgs.python3}/bin/python3 ${./scripts/ensure_homelab_dns.py} ${lib.escapeShellArg domain} ${lib.escapeShellArg lanAddress} ${lib.escapeShellArgs siteNames}";
      LoadCredential = [
        "cloudflare-token:${config.nixSeal.secrets.homelab-cloudflare-dns-token.path}"
        "cloudflare-zone-id:${config.nixSeal.secrets.homelab-cloudflare-zone-id.path}"
      ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };

  homelab.operations.lanHttps = {
    enable = true;
    inherit domain;
    certificateHost = domain;
    listenAddresses = [
      "127.0.0.1"
      lanAddress
    ];
    allowedCIDRs = [ "127.0.0.0/8" ] ++ httpsClientCIDRs;
    sites = {
      t3-desktop = {
        upstream = "http://127.0.0.1:3773";
        streaming = true;
      };
      t3-macbook = {
        # The MacBook owns an outbound SSH tunnel, including when on its VPN.
        upstream = "http://127.0.0.1:3774";
        streaming = true;
      };
      jellyfin = {
        upstream = "http://127.0.0.1:8096";
        streaming = true;
      };
      seerr.upstream = "http://127.0.0.1:${toString config.services.seerr.port}";
      sonarr.upstream = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
      radarr.upstream = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
      lidarr.upstream = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
      prowlarr.upstream = "http://${config.homelab.apps.prowlarr.bindAddress}:${toString config.services.prowlarr.settings.server.port}";
      bazarr.upstream = "http://127.0.0.1:${toString config.services.bazarr.settings.general.port}";
      qbittorrent = {
        upstream = "http://${config.homelab.apps.qbittorrent.bindAddress}:${toString config.homelab.apps.qbittorrent.webuiPort}";
      };
      slskd.upstream = "http://${config.homelab.vpn.namespace.bindAddress}:${toString config.homelab.apps.slskd.webPort}";
      navidrome.upstream = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
      miniflux.upstream = "http://${config.services.miniflux.config.LISTEN_ADDR}";
      news.upstream = "http://${config.services.miniflux.config.LISTEN_ADDR}";
      aurral.upstream = "http://127.0.0.1:3001";
      actual = {
        upstream = "http://127.0.0.1:${toString config.services.actual.settings.port}";
        # Actual enforces OIDC login and manual account creation. Use the same
        # approved LAN and VPN policy as the other authenticated sites.
      };
    }
    // lib.optionalAttrs config.services.keycloak.enable {
      identity = {
        upstream = "http://127.0.0.1:${toString config.services.keycloak.settings.http-port}";
        # Browser OIDC redirects must work for every approved Actual client.
        allowedCIDRs = [
          "127.0.0.0/8"
        ]
        ++ lib.optionals (
          config.services.actual.enable || config.services.wardrowbe.enable
        ) httpsClientCIDRs;
      };
    }
    // lib.optionalAttrs config.services.wardrowbe.enable {
      wardrobe.upstream = "http://127.0.0.1:${toString config.services.wardrowbe.frontendPort}";
    };
  };

  # Retire the scoped phone-access rollout when the generated units take over.
  system.activationScripts.t3PhonePreviewCleanup.text = ''
    for service in nginx blocky; do
      override="/etc/systemd/system.control/$service.service.d/90-t3-phone-preview.conf"
      root="/nix/var/nix/gcroots/t3-phone-$service-unit"
      if [ -L "$override" ] && [ "$(readlink "$override")" = "$root" ]; then
        rm -- "$override"
        rm -f -- "$root" "/nix/var/nix/gcroots/t3-phone-$service-config"
      fi
    done
  '';

  # Actual can transfer financial data in both directions. Do not let nginx
  # spill large imports or responses into temporary files on the plain root.
  services.nginx.virtualHosts."actual.${domain}".locations."/".extraConfig = lib.mkAfter ''
    proxy_request_buffering off;
    proxy_buffering off;
    proxy_ignore_headers X-Accel-Buffering;
    proxy_max_temp_file_size 0;
    client_max_body_size 100m;
  '';

  # The private proxy serves HTTPS only. Keep cleartext HTTP closed.
  networking.firewall.extraInputRules = lib.mkAfter ''
    ${lib.concatMapStringsSep "\n" (source: ''
      iifname { "en*", "eth*", "wl*" } ip saddr ${source.cidr} tcp dport 443 accept comment "private HTTPS from ${source.label}"
    '') httpsClientSources}
  '';

  assertions = [
    {
      assertion =
        config.services.nginx.enable
        && !config.services.jellyfin.openFirewall
        && !builtins.elem 8096 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 443 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 80 config.networking.firewall.allowedTCPPorts;
      message = "Media HTTPS must use source-scoped firewall rules, and direct Jellyfin HTTP must remain closed.";
    }
  ];
}
