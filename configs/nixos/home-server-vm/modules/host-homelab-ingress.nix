{ config, lib, ... }:
let
  baseDomain = "home.ianholloway.com";
  wildcardHost = baseDomain;

  mkHost = service: "${service}.${baseDomain}";

  caddyReverseProxy = upstream: ''
    reverse_proxy ${upstream}
  '';

  mkDefaultVhost = upstream: {
    useACMEHost = wildcardHost;
    extraConfig = caddyReverseProxy upstream;
  };

  mkQbittorrentVhost = upstream: {
    useACMEHost = wildcardHost;
    extraConfig = ''
      reverse_proxy ${upstream} {
        header_up Host {upstream_hostport}
      }
    '';
  };

  servicesByName = {
    jellyfin = {
      displayName = "Jellyfin";
      category = "Media";
      icon = "jellyfin.png";
      description = "Media streaming";
      weight = 10;
      upstream = "127.0.0.1:8096";
    };
    seerr = {
      displayName = "Seerr";
      category = "Media";
      icon = "seerr.png";
      description = "Requests and discovery";
      weight = 20;
      upstream = "127.0.0.1:${toString config.services.seerr.port}";
    };
    sonarr = {
      displayName = "Sonarr";
      category = "Automation";
      icon = "sonarr.png";
      description = "Series automation";
      weight = 10;
      upstream = "127.0.0.1:${toString config.services.sonarr.settings.server.port}";
    };
    radarr = {
      displayName = "Radarr";
      category = "Automation";
      icon = "radarr.png";
      description = "Movie automation";
      weight = 20;
      upstream = "127.0.0.1:${toString config.services.radarr.settings.server.port}";
    };
    lidarr = {
      displayName = "Lidarr";
      category = "Automation";
      icon = "lidarr.png";
      description = "Music automation";
      weight = 30;
      upstream = "127.0.0.1:${toString config.services.lidarr.settings.server.port}";
    };
    readarr = {
      displayName = "Readarr";
      category = "Automation";
      icon = "readarr.png";
      description = "Books automation";
      weight = 40;
      upstream = "127.0.0.1:${toString config.services.readarr.settings.server.port}";
    };
    bazarr = {
      displayName = "Bazarr";
      category = "Automation";
      icon = "bazarr.png";
      description = "Subtitle management";
      weight = 50;
      upstream = "127.0.0.1:${toString config.services.bazarr.listenPort}";
    };
    prowlarr = {
      displayName = "Prowlarr";
      category = "Automation";
      icon = "prowlarr.png";
      description = "Indexer management";
      weight = 60;
      upstream = "127.0.0.1:${toString config.services.prowlarr.settings.server.port}";
    };
    qbittorrent = {
      displayName = "qBittorrent";
      category = "Downloads";
      icon = "qbittorrent.png";
      description = "Torrent client";
      weight = 10;
      upstream = "127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
      vhostBuilder = mkQbittorrentVhost;
    };
    nzbget = {
      displayName = "NZBGet";
      category = "Downloads";
      icon = "nzbget.png";
      description = "Usenet client";
      weight = 20;
      upstream = "127.0.0.1:${toString config.services.nzbget.settings.ControlPort}";
    };
    vaultwarden = {
      displayName = "Vaultwarden";
      category = "Apps";
      icon = "vaultwarden.png";
      description = "Password vault";
      weight = 10;
      upstream = "127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
    };
  };

  categoryServiceOrder = {
    Media = [
      "jellyfin"
      "seerr"
    ];
    Automation = [
      "sonarr"
      "radarr"
      "lidarr"
      "readarr"
      "bazarr"
      "prowlarr"
    ];
    Downloads = [
      "qbittorrent"
      "nzbget"
    ];
    Apps = [ "vaultwarden" ];
  };

  mkHomepageServiceEntry =
    serviceName:
    let
      service = servicesByName.${serviceName};
    in
    {
      "${service.displayName}" = {
        icon = service.icon;
        href = "/${serviceName}/";
        description = service.description;
        weight = service.weight;
      };
    };

  mkServiceVhost =
    serviceName:
    let
      service = servicesByName.${serviceName};
      vhostBuilder = service.vhostBuilder or mkDefaultVhost;
    in
    vhostBuilder service.upstream;

  homepageServices = lib.mapAttrs (
    _category: serviceNames: map mkHomepageServiceEntry serviceNames
  ) categoryServiceOrder;

  serviceVirtualHosts = lib.mapAttrs' (
    serviceName: _service: lib.nameValuePair (mkHost serviceName) (mkServiceVhost serviceName)
  ) servicesByName;

  expectedServiceNames = lib.sort lib.lessThan (lib.attrNames servicesByName);
  configuredServiceNames = lib.sort lib.lessThan (
    lib.concatLists (lib.attrValues categoryServiceOrder)
  );

  serviceRedirectConfig = lib.concatMapStringsSep "\n\n" (serviceName: ''
    handle_path /${serviceName}* {
      redir https://${mkHost serviceName}:{http.request.port}{uri} 302
    }
  '') configuredServiceNames;
in
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "cloudflare-acme-env" ] config;
      message = "age.secrets.cloudflare-acme-env must exist for host-homelab-ingress.";
    }
    {
      assertion = configuredServiceNames == expectedServiceNames;
      message = "categoryServiceOrder must include each service in servicesByName exactly once.";
    }
  ];

  networking.firewall.allowedTCPPorts = [
    22
    443
  ];

  security.acme.defaults.email = "acme@${baseDomain}";

  security.acme.certs.${wildcardHost} = {
    domain = "*.${baseDomain}";
    extraDomainNames = [ baseDomain ];
    dnsProvider = "cloudflare";
    credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-acme-env.path;
    inherit (config.services.caddy) group;
    enableDebugLogs = true;
  };

  services.homepage-dashboard.settings = {
    title = "Home Server VM";
    description = "VM profile for homelab ingress and service validation.";
    color = "zinc";
    layout = {
      Media = {
        style = "row";
        columns = 2;
        icon = "jellyfin.png";
      };
      Automation = {
        style = "row";
        columns = 3;
        icon = "prowlarr.png";
      };
      Downloads = {
        style = "row";
        columns = 2;
        icon = "qbittorrent.png";
      };
      Apps = {
        style = "row";
        columns = 2;
        icon = "vaultwarden.png";
      };
    };
  };

  # Homepage v1 host validation checks the Host header on /api requests.
  # VM hostfwd uses a dynamic non-443 port, so allow all hosts in this local VM profile.
  services.homepage-dashboard.allowedHosts = lib.mkForce "*";

  services.homepage-dashboard.services = homepageServices;

  services.caddy.virtualHosts = {
    ${baseDomain} = {
      useACMEHost = wildcardHost;
      extraConfig = ''
        respond /healthz 200 {
          body "ok"
        }

        ${serviceRedirectConfig}

        ${caddyReverseProxy "127.0.0.1:8082"}
      '';
    };
    ${mkHost "home"} = mkDefaultVhost "127.0.0.1:8082";
  }
  // serviceVirtualHosts;
}
