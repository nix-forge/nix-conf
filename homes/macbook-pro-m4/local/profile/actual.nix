{ config, ... }: {
  services.actual = {
    enable = false;
    dataDir = "${config.xdg.userDirs.documents}/Actual";
  };
}
