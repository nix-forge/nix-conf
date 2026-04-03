{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostPkgs = import pkgs.path {
    system = "aarch64-darwin";
    overlays = [ ];
    config = {
      allowUnfree = true;
    };
  };
  curl = lib.getExe pkgs.curl;
  python = lib.getExe (pkgs.python3.withPackages (ps: [ ps.requests ]));
  afterServices = [
    "network-online.target"
    "traefik.service"
  ]
  ++ lib.optionals config.my.media.services.jellyfin.enable [ "jellyfin.service" ]
  ++ lib.optionals config.my.media.services.jellyseerr.enable [ "jellyseerr.service" ]
  ++ lib.optionals config.my.media.services.vaultwarden.enable [ "vaultwarden.service" ]
  ++ lib.optionals config.my.media.services.torrent.enable [
    "docker.service"
    "nzbget.service"
  ]
  ++ lib.optionals config.my.media.services.arr.enable [
    "radarr.service"
    "sonarr.service"
    "prowlarr.service"
    "bazarr.service"
  ];
  selfTestScript = lib.concatStringsSep "\n" (
    [
      "set -eEu"
      "trap 'echo MEDIA_VM_SELF_TEST_FAIL' ERR"
      "check() {"
      "  local name=$1"
      "  shift"
      "  echo \"MEDIA_VM_CHECK_\${name}_START\""
      "  ${curl} --silent --show-error --location --insecure --retry 15 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 10 -o /dev/null -I \"$@\""
      "  echo \"MEDIA_VM_CHECK_\${name}_PASS\""
      "}"
      "check_status() {"
      "  local name=$1"
      "  local expected=$2"
      "  shift 2"
      "  echo \"MEDIA_VM_CHECK_\${name}_START\""
      "  local code"
      "  code=$(${curl} --silent --show-error --location --insecure --retry 15 --retry-delay 2 --retry-connrefused --retry-all-errors --connect-timeout 2 --max-time 10 -o /dev/null -w '%{http_code}' \"$@\")"
      "  [ \"$code\" = \"$expected\" ]"
      "  echo \"MEDIA_VM_CHECK_\${name}_PASS\""
      "}"
      "check_cmd() {"
      "  local name=$1"
      "  shift"
      "  echo \"MEDIA_VM_CHECK_\${name}_START\""
      "  eval \"$*\""
      "  echo \"MEDIA_VM_CHECK_\${name}_PASS\""
      "}"
      "check TRAEFIK_HTTP http://127.0.0.1:${toString config.my.media.ports.traefikHttp}"
    ]
    ++ lib.optionals config.my.media.services.jellyfin.enable [
      "check JELLYFIN_ROUTE -H Host:${config.my.media.hosts.jellyfin} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.jellyseerr.enable [
      "check JELLYSEERR_ROUTE -H Host:${config.my.media.hosts.jellyseerr} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.arr.enable [
      "check RADARR_ROUTE -H Host:${config.my.media.hosts.radarr} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check SONARR_ROUTE -H Host:${config.my.media.hosts.sonarr} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check PROWLARR_ROUTE -H Host:${config.my.media.hosts.prowlarr} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check BAZARR_ROUTE -H Host:${config.my.media.hosts.bazarr} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.vaultwarden.enable [
      "check VAULTWARDEN_ROUTE -H Host:${config.my.media.hosts.vaultwarden} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check_status VAULTWARDEN_PUBLIC_DENY 404 -H Host:${config.my.media.hosts.vaultwardenPublic} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check VAULTWARDEN_PUBLIC_ALLOW -H Host:${config.my.media.hosts.vaultwardenPublic} -H Cf-Access-Jwt-Assertion:test-token https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.torrent.enable [
      "check QBITTORRENT_ROUTE -H Host:${config.my.media.hosts.qbittorrent} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check NZBGET_ROUTE -H Host:${config.my.media.hosts.nzbget} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check_cmd GLUETUN_HEALTH 'test -f /etc/systemd/system/docker-gluetun.service'"
      "check_cmd QBITTORRENT_NETNS_MODE 'grep -R -q -- --network=container:gluetun /nix/store/*docker-qbittorrent-start*/bin/*'"
      "check_cmd QBITTORRENT_NETNS_SHARED 'grep -R -F -q -- \"-p ${toString config.my.media.ports.qbittorrent}:8080/tcp\" /nix/store/*docker-gluetun-start*/bin/*'"
      "check_cmd QBITTORRENT_DIRECT_EXPOSED '! grep -R -F -q -- \"-p \" /nix/store/*docker-qbittorrent-start*/bin/* && ! grep -R -F -q -- --publish /nix/store/*docker-qbittorrent-start*/bin/*'"
    ]
    ++ lib.optionals config.my.media.services.pihole.enable [
      "check PIHOLE_ROUTE -H Host:${config.my.media.hosts.pihole} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.homebridge.enable [
      "check HOMEBRIDGE_ROUTE -H Host:${config.my.media.hosts.homebridge} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.scrypted.enable [
      "check SCRYPTED_ROUTE -H Host:${config.my.media.hosts.scrypted} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.jellyfin.enable [
      "check_status JELLYFIN_PUBLIC_DENY 404 -H Host:${config.my.media.hosts.jellyfinPublic} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check JELLYFIN_PUBLIC_ALLOW -H Host:${config.my.media.hosts.jellyfinPublic} -H Cf-Access-Jwt-Assertion:test-token https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ lib.optionals config.my.media.services.jellyseerr.enable [
      "check_status JELLYSEERR_PUBLIC_DENY 404 -H Host:${config.my.media.hosts.jellyseerrPublic} https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
      "check JELLYSEERR_PUBLIC_ALLOW -H Host:${config.my.media.hosts.jellyseerrPublic} -H Cf-Access-Jwt-Assertion:test-token https://127.0.0.1:${toString config.my.media.ports.traefikHttps}"
    ]
    ++ [ "echo MEDIA_VM_SELF_TEST_PASS" ]
  );
in
{
  networking.firewall.enable = lib.mkForce false;

  virtualisation.vmVariant = {
    virtualisation.host.pkgs = hostPkgs;
    virtualisation.cores = 4;
    virtualisation.memorySize = 8192;
    virtualisation.vlans = lib.mkForce [ ];

    networking.nameservers = lib.mkForce [
      "1.1.1.1"
      "8.8.8.8"
    ];

    virtualisation.forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.address = config.my.media.network.lanAddress;
        guest.port = config.my.media.ports.ssh;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8080;
        guest.address = config.my.media.network.lanAddress;
        guest.port = config.my.media.ports.traefikHttp;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8443;
        guest.address = config.my.media.network.lanAddress;
        guest.port = config.my.media.ports.traefikHttps;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 8096;
        guest.address = config.my.media.network.lanAddress;
        guest.port = config.my.media.ports.jellyfin;
      }
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 5055;
        guest.address = config.my.media.network.lanAddress;
        guest.port = config.my.media.ports.jellyseerr;
      }
    ];

    services.qemuGuest.enable = true;

    systemd.services.media-vm-self-test = {
      description = "Media server VM internal smoke tests";
      wantedBy = [ "multi-user.target" ];
      wants = afterServices;
      after = afterServices;
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = selfTestScript;
    };
  };

  services.openssh.enable = true;
  users.allowNoPasswordLogin = lib.mkForce true;
}
