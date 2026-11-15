{ config, ... }:
let
  root = "${config.homelab.storage.downloadsDir}/soulseek";
in
{
  nixSeal.secrets.music-discovery-slskd-settings = {
    owner = "root";
    group = "root";
    mode = "0400";
    phase = "services";
    restartUnits = [ "slskd.service" ];
  };

  homelab.apps.slskd = {
    enable = true;
    preparationUnit = "soulseek-directories";
    credentialsFile = config.nixSeal.secrets.music-discovery-slskd-settings.path;
    downloadGroup = config.homelab.storage.group;
    downloadDirectoryMode = "2770";
    downloadsDir = "${root}/complete";
    incompleteDir = "${root}/incomplete";
  };

  systemd.services.slskd = {
    requires = [
      "nix-seal-activate.service"
      "soulseek-directories.service"
    ];
    after = [
      "nix-seal-activate.service"
      "soulseek-directories.service"
    ];
    serviceConfig = {
      SupplementaryGroups = [ config.homelab.storage.group ];
      InaccessiblePaths = [ config.homelab.storage.libraryDir ];
    };
  };

}
