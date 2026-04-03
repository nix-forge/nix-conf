{ config, lib, ... }:
let
  cfTestCidrs = [
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
in
{
  users.mutableUsers = lib.mkForce true;
  boot.tmp.cleanOnBoot = lib.mkForce true;

  fileSystems."/" = lib.mkForce {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=755" ];
  };

  fileSystems."/boot" = lib.mkForce {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" ];
    neededForBoot = true;
  };

  swapDevices = lib.mkForce [ ];

  my.media.network = {
    manageHostNetworking = lib.mkForce false;
    interface = lib.mkForce "eth0";
    lanAddress = lib.mkForce "10.0.2.15";
    lanPrefixLength = lib.mkForce 24;
    lanCidrs = lib.mkForce [ "10.0.2.0/24" ];
    trustedProxyCidrs = lib.mkForce (
      cfTestCidrs
      ++ [
        "127.0.0.1/32"
        "10.0.2.0/24"
      ]
    );
    nameservers = lib.mkForce [ "1.1.1.1" ];
  };

  my.media.storage = {
    diskId = lib.mkForce "vm-not-used";
    stateDir = lib.mkForce "/srv/state";
    mediaDir = lib.mkForce "/srv/media";
    downloadsDir = lib.mkForce "/srv/downloads";
    swapSize = lib.mkForce "2G";
  };

  my.media.hosts = {
    vaultwarden = lib.mkForce "vaultwarden.test";
    jellyfin = lib.mkForce "jellyfin.test";
    jellyseerr = lib.mkForce "jellyseerr.test";
    radarr = lib.mkForce "radarr.test";
    sonarr = lib.mkForce "sonarr.test";
    prowlarr = lib.mkForce "prowlarr.test";
    bazarr = lib.mkForce "bazarr.test";
    qbittorrent = lib.mkForce "qbittorrent.test";
    nzbget = lib.mkForce "nzbget.test";
    homebridge = lib.mkForce "homebridge.test";
    scrypted = lib.mkForce "scrypted.test";
    pihole = lib.mkForce "pihole.test";

    vaultwardenPublic = lib.mkForce "vaultwarden.public.test";
    jellyfinPublic = lib.mkForce "jellyfin.public.test";
    jellyseerrPublic = lib.mkForce "jellyseerr.public.test";
  };

  my.media.ddns = {
    zone = lib.mkForce "test";
    domain = lib.mkForce "home.test";
    interval = lib.mkForce "10min";
  };

  my.media.cloudflare = {
    tunnelId = lib.mkForce "11111111-1111-1111-1111-111111111111";
    accessAudTag = lib.mkForce "media-vm-aud";
    accessProtectedHosts = lib.mkForce [
      config.my.media.hosts.vaultwardenPublic
      config.my.media.hosts.jellyfinPublic
      config.my.media.hosts.jellyseerrPublic
    ];
  };
}
