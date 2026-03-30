{ lib, config, ... }:
let
  cfg = config.homelab.media.jellyfin;
in
{
  options.homelab.media.jellyfin = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/jellyfin";
      description = "Jellyfin state directory.";
    };

    stackRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media-stack";
      description = "Shared media stack root.";
    };

    primaryGroup = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
      description = "Primary group for Jellyfin service runtime.";
    };

    mediaGroup = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared media library group.";
    };
  };

  config = {
    services.nginx.virtualHosts."_".locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.tailscaleTls.enable {
        "= /jellyfin" = {
          return = "302 /jellyfin/";
        };
        "/jellyfin/" = {
          proxyPass = "http://127.0.0.1:8096/";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Prefix /jellyfin;
            proxy_buffering off;
          '';
        };
      })
    ];

    services.nginx.virtualHosts.vm-http.locations = lib.mkMerge [
      (lib.mkIf config.homelab.proxy.vmHttpAccess.enable {
        "= /jellyfin" = {
          return = "302 /jellyfin/";
        };
        "/jellyfin/" = {
          proxyPass = "http://127.0.0.1:8096/";
          recommendedProxySettings = true;
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-Forwarded-Prefix /jellyfin;
            proxy_buffering off;
          '';
        };
      })
    ];

    services.homepage-dashboard.services.Media = [
      {
        Jellyfin = {
          icon = "jellyfin.png";
          href = "/jellyfin/";
          description = "Stream the main library with the Tailscale cert in front.";
          weight = 10;
        };
      }
    ];

    users.groups.${cfg.primaryGroup} = { };
    users.groups.${cfg.mediaGroup} = { };

    users.users.jellyfin.extraGroups = lib.mkAfter [ cfg.mediaGroup ];

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 jellyfin ${cfg.primaryGroup} - -"
      "d ${cfg.stackRoot} 0755 root root - -"
      "d ${cfg.stackRoot}/data 0755 root root - -"
      "d ${cfg.stackRoot}/data/media 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/movies 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/tv 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/music 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/books 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/audiobooks 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/data/media/books/comics 2770 root ${cfg.mediaGroup} - -"
      "d ${cfg.stackRoot}/cache 0755 root root - -"
      "d ${cfg.stackRoot}/cache/jellyfin 2750 jellyfin ${cfg.primaryGroup} - -"
    ];

    services.jellyfin = {
      enable = true;
      user = "jellyfin";
      group = cfg.primaryGroup;
      dataDir = cfg.stateDir;
      openFirewall = false;
    };
  };
}
