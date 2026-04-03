{
  profile ? "home-server",
}:
{ lib, config, ... }:
let
  stack = import ./stack-values.nix { inherit profile; };
in
{
  users.groups.${stack.downloadsGroup}.gid = stack.downloadsGid;
  users.groups.${stack.mediaGroup}.gid = stack.mediaGid;

  users.users.jellyfin.extraGroups = lib.mkIf config.services.jellyfin.enable (
    lib.mkAfter [ stack.mediaGroup ]
  );
  users.users.qbittorrent.extraGroups = lib.mkIf config.services.qbittorrent.enable (
    lib.mkAfter [ stack.downloadsGroup ]
  );
  users.users.nzbget.extraGroups = lib.mkIf config.services.nzbget.enable (
    lib.mkAfter [ stack.downloadsGroup ]
  );
  users.users.sonarr.extraGroups = lib.mkIf config.services.sonarr.enable (
    lib.mkAfter [
      stack.downloadsGroup
      stack.mediaGroup
    ]
  );
  users.users.radarr.extraGroups = lib.mkIf config.services.radarr.enable (
    lib.mkAfter [
      stack.downloadsGroup
      stack.mediaGroup
    ]
  );
  users.users.lidarr.extraGroups = lib.mkIf config.services.lidarr.enable (
    lib.mkAfter [
      stack.downloadsGroup
      stack.mediaGroup
    ]
  );
  users.users.readarr.extraGroups = lib.mkIf config.services.readarr.enable (
    lib.mkAfter [
      stack.downloadsGroup
      stack.mediaGroup
    ]
  );
  users.users.bazarr.extraGroups = lib.mkIf config.services.bazarr.enable (
    lib.mkAfter [
      stack.downloadsGroup
      stack.mediaGroup
    ]
  );

  systemd.tmpfiles.rules = [
    "d ${stack.stackRoot} 0755 root root - -"
    "d ${stack.stackRoot}/data 0755 root root - -"
    "d ${stack.stackRoot}/cache 0755 root root - -"
    "d ${stack.stackRoot}/cache/jellyfin 2750 jellyfin jellyfin - -"
    "d ${stack.stackRoot}/cache/qbittorrent 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/media 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/movies 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/tv 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/music 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/books 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/books/books 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/books/audiobooks 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/media/books/comics 2770 root ${stack.mediaGroup} - -"
    "d ${stack.stackRoot}/data/torrents 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/torrents/incomplete 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/torrents/movies 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/torrents/tv 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/torrents/music 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/torrents/books 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet/incomplete 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet/movies 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet/tv 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet/music 2770 root ${stack.downloadsGroup} - -"
    "d ${stack.stackRoot}/data/usenet/books 2770 root ${stack.downloadsGroup} - -"
  ];
}
