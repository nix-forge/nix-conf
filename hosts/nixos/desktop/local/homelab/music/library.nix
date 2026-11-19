{ config, lib, ... }: {
  options.homelab.desktopMusic.libraryDir = lib.mkOption {
    type = lib.types.nonEmptyStr;
    default = "${config.homelab.storage.libraryDir}/music";
    readOnly = true;
    internal = true;
    description = "Shared desktop music library used by Aurral, Lidarr, Navidrome and Jellyfin.";
  };
}
