{ config, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
in
{
  programs.feishin.managedLogin = {
    name = "Homelab Music";
    url = if isDarwin then "http://127.0.0.1:45330" else "http://127.0.0.1:4533";
    usernameFile = config.nixSeal.secrets.homelab-navidrome-listener-username.path;
    passwordFile = config.nixSeal.secrets.feishin-listener-password.path;
  };
  services.sshForwards.feishin-navidrome-tunnel = {
    enable = isDarwin;
    host = "desktop";
    bindPort = 45330;
    targetPort = 4533;
  };

  # A single sealed password is delivered to the music server and both homes.
  # Startup provisioning refreshes the app session from these runtime files.
  nixSeal.secrets.homelab-navidrome-listener-username = {
    shared = true;
    mode = "0600";
  };
  nixSeal.secrets.feishin-listener-password = {
    shared = true;
    mode = "0600";
  };

}
