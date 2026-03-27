{ config, lib, ... }:
let
  cfg = config.my.media;
in
{
  config = lib.mkIf (cfg.enable && cfg.services.ddns.enable) {
    services.ddclient = {
      enable = true;
      protocol = "cloudflare";
      username = "token";
      passwordFile = config.age.secrets.${cfg.secrets.cloudflareDdnsToken}.path;
      inherit (cfg.ddns) zone;
      domains = [ cfg.ddns.domain ];
      inherit (cfg.ddns) interval;
      usev4 = "webv4";
      usev6 = "";
      extraConfig = "webv4=api.ipify.org";
      ssl = true;
      verbose = false;
    };
  };
}
