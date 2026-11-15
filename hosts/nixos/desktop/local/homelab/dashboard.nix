{ config, lib, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  domain = config.homelab.operations.lanHttps.domain;
  localSites = config.homelab.operations.lanHttps.sites;
  # The Pi's published site names come from the shared host network inventory.
  piCatalog = lib.genAttrs network.raspberryPiHttpsSites (name: {
    url = "https://${name}.${domain}";
    group = "Raspberry Pi";
    description = "Raspberry Pi";
  });
  # These fields only refine presentation. Site discovery and URLs come from
  # the HTTPS declarations, so a new site appears without a dashboard edit.
  presentation = {
    jellyfin = {
      title = "Jellyfin";
      group = "Media";
      icon = "jellyfin";
      description = "Movies and shows";
    };
    seerr = {
      title = "Seerr";
      group = "Media";
      icon = "jellyseerr";
      description = "Media requests";
    };
    navidrome = {
      title = "Navidrome";
      group = "Media";
      icon = "navidrome";
      description = "Music library";
    };
    audiobookshelf = {
      title = "Audiobookshelf";
      group = "Reading";
      icon = "audiobookshelf";
      description = "Listen to audiobooks";
    };
    aurral = {
      title = "Aurral";
      group = "Media";
    };
    news = {
      title = "News";
      group = "Reading";
      description = "News reader";
    };
    miniflux = {
      title = "Miniflux";
      group = "Reading";
      icon = "miniflux";
      description = "Feed reader";
    };
    bookorbit = {
      title = "BookOrbit";
      group = "Reading";
      description = "Find and request books";
    };
    komga = {
      title = "Komga";
      group = "Reading";
      icon = "komga";
      description = "Read ebooks and comics";
    };
    sonarr = {
      title = "Sonarr";
      group = "Automation";
      icon = "sonarr";
    };
    radarr = {
      title = "Radarr";
      group = "Automation";
      icon = "radarr";
    };
    lidarr = {
      title = "Lidarr";
      group = "Automation";
      icon = "lidarr";
    };
    prowlarr = {
      title = "Prowlarr";
      group = "Automation";
      icon = "prowlarr";
    };
    bazarr = {
      title = "Bazarr";
      group = "Automation";
      icon = "bazarr";
    };
    qbittorrent = {
      title = "qBittorrent";
      group = "Automation";
      icon = "qbittorrent";
    };
    slskd = {
      title = "Slskd";
      group = "Automation";
    };
    actual = {
      title = "Actual Budget";
      group = "Tools";
      icon = "actual-budget";
    };
    pdf = {
      title = "Stirling PDF";
      group = "Tools";
      icon = "stirling-pdf";
    };
    wardrobe = {
      title = "Wardrobe";
      group = "Tools";
    };
    homebridge = {
      title = "Homebridge";
      icon = "homebridge";
      description = "HomeKit bridge";
    };
    scrypted = {
      title = "Scrypted";
      icon = "scrypted";
      description = "Camera and device bridge";
    };
    identity = {
      title = "Identity";
      icon = "keycloak";
    };
  };
  published = lib.filterAttrs (
    name: _: builtins.hasAttr name localSites || builtins.elem name network.raspberryPiHttpsSites
  ) presentation;
in
{
  nixSeal.secrets.homelab-dashboard-env = {
    phase = "services";
    restartUnits = [ "homepage-dashboard.service" ];
  };

  homelab.operations.dashboard = {
    enable = true;
    exposeViaLanHttps = true;
    authEnvironmentFile = config.nixSeal.secrets.homelab-dashboard-env.path;
    groupOrder = [
      "Media"
      "Reading"
      "Automation"
      "Tools"
      "Services"
      "Desktop only"
      "Raspberry Pi"
    ];
    groupColumns = {
      "Desktop only" = 2;
      "Raspberry Pi" = 2;
    };
    catalog = lib.recursiveUpdate piCatalog published;
  };
}
