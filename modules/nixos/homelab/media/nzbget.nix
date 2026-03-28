{ pkgs, ... }:
{
  services.nzbget = {
    enable = true;
    package = pkgs.nzbget;
    user = "nzbget";
    group = "media";
    settings = {
      ControlIP = "127.0.0.1";
      ControlPort = 6789;
    };
  };
}
