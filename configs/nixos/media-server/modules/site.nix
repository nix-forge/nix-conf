{ config, lib, ... }:
{
  users.mutableUsers = lib.mkForce true;
  boot.tmp.cleanOnBoot = lib.mkForce true;

  my.media = {
    enable = true;

    network = {
      interface = "eno1";
      lanAddress = "192.168.1.10";
      lanPrefixLength = 24;
      lanCidrs = [ "192.168.1.0/24" ];
      trustedProxyCidrs = [
        "173.245.48.0/20"
        "103.21.244.0/22"
        "103.22.200.0/22"
        "103.31.4.0/22"
        "141.101.64.0/18"
        "108.162.192.0/18"
        "190.93.240.0/20"
        "188.114.96.0/20"
        "197.234.240.0/22"
        "198.41.128.0/17"
        "162.158.0.0/15"
        "104.16.0.0/13"
        "104.24.0.0/14"
        "172.64.0.0/13"
        "131.0.72.0/22"
      ];
      nameservers = [
        "127.0.0.1"
        "1.1.1.1"
      ];
    };

    storage = {
      diskId = "REPLACE_WITH_DISK_BY_ID";
      stateDir = "/srv/state";
      mediaDir = "/srv/media";
      downloadsDir = "/srv/downloads";
      swapSize = "16G";
    };

    hosts = {
      vaultwarden = "vaultwarden.lan";
      jellyfin = "jellyfin.lan";
      jellyseerr = "jellyseerr.lan";
      radarr = "radarr.lan";
      sonarr = "sonarr.lan";
      prowlarr = "prowlarr.lan";
      bazarr = "bazarr.lan";
      qbittorrent = "qbittorrent.lan";
      nzbget = "nzbget.lan";
      homebridge = "homebridge.lan";
      scrypted = "scrypted.lan";
      pihole = "pihole.lan";

      vaultwardenPublic = "vaultwarden.example.com";
      jellyfinPublic = "jellyfin.example.com";
      jellyseerrPublic = "jellyseerr.example.com";
    };

    ddns = {
      zone = "example.com";
      domain = "home.example.com";
      interval = "5min";
    };

    cloudflare = {
      tunnelId = "00000000-0000-0000-0000-000000000000";
      accessAudTag = "REPLACE_WITH_CLOUDFLARE_ACCESS_AUD";
      accessProtectedHosts = [
        "${config.my.media.hosts.vaultwardenPublic}"
        "${config.my.media.hosts.jellyfinPublic}"
        "${config.my.media.hosts.jellyseerrPublic}"
      ];
    };

    secrets = {
      cloudflareDdnsToken = "cloudflare-ddns-token";
      vaultwardenEnv = "vaultwarden-env";
      vpnGluetunEnv = "vpn-gluetun-env";
      qbittorrentEnv = "qbittorrent-env";
      piholeEnv = "pihole-env";
      cloudflaredCreds = "cloudflared-credentials";
      cloudflaredCert = "cloudflared-cert";
      homebridgeEnv = "homebridge-env";
      scryptedEnv = "scrypted-env";
    };

    services = {
      traefik.enable = true;
      arr.enable = true;
      jellyfin.enable = true;
      jellyseerr.enable = true;
      vaultwarden.enable = true;
      ddns.enable = true;
      torrent.enable = true;
      pihole.enable = true;
      homebridge.enable = true;
      scrypted.enable = true;
      cloudflared.enable = false;
      fail2ban.enable = true;
    };
  };
}
