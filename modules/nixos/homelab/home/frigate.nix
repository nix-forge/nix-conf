{ pkgs, ... }:
{
  services.frigate = {
    enable = true;
    package = pkgs.frigate;
    checkConfig = true;
    hostname = "127.0.0.1";
    settings = {
      mqtt.enable = false;
      cameras = { };
    };
  };

  systemd.services.frigate.environment = {
    FRIGATE_BASE_PATH = "/frigate";
  };
}
