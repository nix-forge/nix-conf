{ config, ... }: {
  homelab.music.shuffle = {
    enable = true;
    usernameFile = config.nixSeal.secrets.homelab-navidrome-listener-username.path;
    passwordFile = config.nixSeal.secrets.feishin-listener-password.path;
    readyUnits = [ "music-discovery-bootstrap.service" ];
    requiredMounts = config.homelab.storage.requiredMounts;
  };
}
