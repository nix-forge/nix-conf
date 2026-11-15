{
  # The upstream client owns login in its UI; retain the private server tunnel.
  services.sshForwards.feishin-navidrome-tunnel = {
    enable = true;
    host = "desktop";
    bindPort = 45330;
    targetPort = 4533;
  };
}
