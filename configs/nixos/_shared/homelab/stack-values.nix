{
  profile ? "home-server",
}:
let
  isVm = profile == "home-server-vm";

  baseDomain = "home.ianholloway.com";

  serviceOrder = {
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
in
{
  inherit profile isVm baseDomain;

  acmeEmail = "acme@${baseDomain}";
  wildcardHost = baseDomain;

  ingressAuth = {
    enabled = false;
    envSecretName = "homelab-ingress-auth-env";
    usernameEnv = "HOMELAB_INGRESS_AUTH_USER";
    passwordHashEnv = "HOMELAB_INGRESS_AUTH_PASSWORD_HASH";
  };

  stackRoot = "/srv/media-stack";
  mediaGroup = "media";
  mediaGid = 2000;
  downloadsGroup = "downloads";
  downloadsGid = 2010;

  vpn = {
    interface = "wg-mullvad";
    interfaceAddress4 = "10.71.216.231";
    interfaceAddress6 = "fc00:bbbb:bbbb:bb01::8:d8e6";
    dns = [ "10.64.0.1" ];
    table = 51820;

    peer = {
      publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
      endpoint = "138.199.43.91:51820";
      allowedIPs = [
        "0.0.0.0/0"
        "::/0"
      ];
      persistentKeepalive = 25;
    };

    users = [
      "qbittorrent"
      "nzbget"
      "prowlarr"
    ];

    userUids = {
      qbittorrent = 2001;
      nzbget = 2002;
      prowlarr = 2003;
    };

    allowedIPv4Cidrs = [
      "127.0.0.0/8"
      "100.64.0.0/10"
      "169.254.0.0/16"
    ];

    allowedIPv6Cidrs = [
      "::1/128"
      "fd7a:115c:a1e0::/48"
      "fe80::/10"
    ];
  };

  services = {
    jellyfin = {
      displayName = "Jellyfin";
      category = "Media";
      icon = "jellyfin.png";
      description = "Media streaming";
      weight = 10;
      requireIngressAuth = false;
      upstream = "127.0.0.1:8096";
      homepageHref = if isVm then "/jellyfin/" else "https://jellyfin.${baseDomain}/";
    };
    seerr = {
      displayName = "Seerr";
      category = "Media";
      icon = "seerr.png";
      description = "Requests and discovery";
      weight = 20;
      requireIngressAuth = true;
      port = 5055;
      upstream = "127.0.0.1:5055";
      homepageHref = if isVm then "/seerr/" else "https://seerr.${baseDomain}/";
    };
    sonarr = {
      displayName = "Sonarr";
      category = "Automation";
      icon = "sonarr.png";
      description = "Series automation";
      weight = 10;
      requireIngressAuth = true;
      port = 8989;
      upstream = "127.0.0.1:8989";
      homepageHref = if isVm then "/sonarr/" else "https://sonarr.${baseDomain}/";
    };
    radarr = {
      displayName = "Radarr";
      category = "Automation";
      icon = "radarr.png";
      description = "Movie automation";
      weight = 20;
      requireIngressAuth = true;
      port = 7878;
      upstream = "127.0.0.1:7878";
      homepageHref = if isVm then "/radarr/" else "https://radarr.${baseDomain}/";
    };
    lidarr = {
      displayName = "Lidarr";
      category = "Automation";
      icon = "lidarr.png";
      description = "Music automation";
      weight = 30;
      requireIngressAuth = true;
      port = 8686;
      upstream = "127.0.0.1:8686";
      homepageHref = if isVm then "/lidarr/" else "https://lidarr.${baseDomain}/";
    };
    readarr = {
      displayName = "Readarr";
      category = "Automation";
      icon = "readarr.png";
      description = "Books automation";
      weight = 40;
      requireIngressAuth = true;
      port = 8787;
      upstream = "127.0.0.1:8787";
      homepageHref = if isVm then "/readarr/" else "https://readarr.${baseDomain}/";
    };
    bazarr = {
      displayName = "Bazarr";
      category = "Automation";
      icon = "bazarr.png";
      description = "Subtitle management";
      weight = 50;
      requireIngressAuth = true;
      port = 6767;
      upstream = "127.0.0.1:6767";
      homepageHref = if isVm then "/bazarr/" else "https://bazarr.${baseDomain}/";
    };
    prowlarr = {
      displayName = "Prowlarr";
      category = "Automation";
      icon = "prowlarr.png";
      description = "Indexer management";
      weight = 60;
      requireIngressAuth = true;
      port = 9696;
      upstream = "127.0.0.1:9696";
      homepageHref = if isVm then "/prowlarr/" else "https://prowlarr.${baseDomain}/";
    };
    qbittorrent = {
      displayName = "qBittorrent";
      category = "Downloads";
      icon = "qbittorrent.png";
      description = "Torrent client";
      weight = 10;
      requireIngressAuth = true;
      webuiPort = 8081;
      torrentingPort = 51413;
      upstream = "127.0.0.1:8081";
      homepageHref = if isVm then "/qbittorrent/" else "https://qbittorrent.${baseDomain}/";
      reverseProxyNeedsHostHeader = true;
    };
    nzbget = {
      displayName = "NZBGet";
      category = "Downloads";
      icon = "nzbget.png";
      description = "Usenet client";
      weight = 20;
      requireIngressAuth = true;
      controlPort = 6789;
      upstream = "127.0.0.1:6789";
      homepageHref = if isVm then "/nzbget/" else "https://nzbget.${baseDomain}/";
    };
    vaultwarden = {
      displayName = "Vaultwarden";
      category = "Apps";
      icon = "vaultwarden.png";
      description = "Password vault";
      weight = 10;
      requireIngressAuth = false;
      rocketPort = 8222;
      upstream = "127.0.0.1:8222";
      homepageHref = if isVm then "/vaultwarden/" else "https://vaultwarden.${baseDomain}/";
    };
  };

  inherit serviceOrder;
}
