{ lib, ... }:
let
  stackRoot = "/srv/media-stack";
  downloadsGroup = "downloads";
  mediaGroup = "media";
in
{
  users.groups.${downloadsGroup}.gid = 2010;
  users.groups.${mediaGroup}.gid = 2000;

  users.users.jellyfin.extraGroups = lib.mkAfter [ mediaGroup ];
  users.users.qbittorrent.extraGroups = lib.mkAfter [ downloadsGroup ];
  users.users.nzbget.extraGroups = lib.mkAfter [ downloadsGroup ];
  users.users.sonarr.extraGroups = lib.mkAfter [
    downloadsGroup
    mediaGroup
  ];
  users.users.radarr.extraGroups = lib.mkAfter [
    downloadsGroup
    mediaGroup
  ];
  users.users.lidarr.extraGroups = lib.mkAfter [
    downloadsGroup
    mediaGroup
  ];
  users.users.readarr.extraGroups = lib.mkAfter [
    downloadsGroup
    mediaGroup
  ];
  users.users.bazarr.extraGroups = lib.mkAfter [
    downloadsGroup
    mediaGroup
  ];

  systemd.tmpfiles.rules = [
    "d ${stackRoot}/data 0755 root root - -"
    "d ${stackRoot}/cache 0755 root root - -"
    "d ${stackRoot}/cache/jellyfin 2750 jellyfin jellyfin - -"
    "d ${stackRoot}/cache/qbittorrent 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/media 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/movies 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/tv 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/music 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/books 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/books/books 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/books/audiobooks 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/media/books/comics 2770 root ${mediaGroup} - -"
    "d ${stackRoot}/data/torrents 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/torrents/incomplete 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/torrents/movies 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/torrents/tv 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/torrents/music 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/torrents/books 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet/incomplete 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet/movies 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet/tv 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet/music 2770 root ${downloadsGroup} - -"
    "d ${stackRoot}/data/usenet/books 2770 root ${downloadsGroup} - -"
  ];
}
