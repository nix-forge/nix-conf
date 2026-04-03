{ config, lib, ... }:
let
  cfg = config.my.media;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";

    networking.hosts."127.0.0.1" = [
      cfg.hosts.jellyfin
      cfg.hosts.jellyseerr
      cfg.hosts.radarr
      cfg.hosts.sonarr
      cfg.hosts.prowlarr
      cfg.hosts.bazarr
      cfg.hosts.qbittorrent
      cfg.hosts.nzbget
      cfg.hosts.vaultwarden
    ];

    networking.firewall = lib.mkIf cfg.network.manageHostNetworking {
      enable = true;
      allowedTCPPorts = [ cfg.ports.ssh ];
      allowedUDPPorts = [ cfg.ports.dns ];
      interfaces.${cfg.network.interface} = {
        allowedUDPPorts = [ cfg.ports.dns ];
        allowedTCPPorts = [
          cfg.ports.dns
          cfg.ports.traefikHttp
          cfg.ports.traefikHttps
        ];
      };
    };

    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };

    services.fail2ban = lib.mkIf cfg.services.fail2ban.enable {
      enable = true;
      maxretry = 5;
      bantime = "6h";
      ignoreIP = cfg.network.lanCidrs;
    };

    services.resolved.enable = false;
  };
}
