{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.my.media;
  state = cfg.storage.stateDir;
  hasPiholeFtl = lib.hasAttrByPath [ "services" "pihole-ftl" "enable" ] options;
in
{
  config = lib.mkIf cfg.enable {
    services.pihole-ftl = lib.mkIf (cfg.services.pihole.enable && hasPiholeFtl) {
      enable = true;
      openFirewallDNS = false;
      openFirewallDHCP = false;
      openFirewallWebserver = false;
      stateDirectory = "${state}/pihole";
      settings = {
        webserver.port = cfg.ports.pihole;
        dns.port = cfg.ports.dns;
      };
    };

    virtualisation.oci-containers.containers.pihole =
      lib.mkIf (cfg.services.pihole.enable && !hasPiholeFtl)
        {
          image = "pihole/pihole:2025.02.2";
          autoStart = true;
          environmentFiles = [ config.age.secrets.${cfg.secrets.piholeEnv}.path ];
          volumes = [
            "${state}/pihole:/etc/pihole"
            "${state}/pihole-dnsmasq:/etc/dnsmasq.d"
          ];
          ports = [ "127.0.0.1:${toString cfg.ports.pihole}:80/tcp" ];
          extraOptions = [ "--security-opt=no-new-privileges:true" ];
        };

    virtualisation.oci-containers.containers.homebridge = lib.mkIf cfg.services.homebridge.enable {
      image = "homebridge/homebridge:2024-12-18";
      autoStart = true;
      environmentFiles = [ config.age.secrets.${cfg.secrets.homebridgeEnv}.path ];
      volumes = [ "${state}/homebridge:/homebridge" ];
      ports = [ "127.0.0.1:${toString cfg.ports.homebridge}:8581/tcp" ];
      extraOptions = [ "--security-opt=no-new-privileges:true" ];
    };

    systemd.tmpfiles.rules =
      lib.optionals cfg.services.pihole.enable [ "d ${state}/pihole-dnsmasq 0750 root media -" ]
      ++ lib.optionals cfg.services.scrypted.enable [ "d ${state}/scrypted 0750 root media -" ];

    virtualisation.oci-containers.containers.scrypted = lib.mkIf cfg.services.scrypted.enable {
      image = "ghcr.io/koush/scrypted:v0.124.0";
      autoStart = true;
      environmentFiles = [ config.age.secrets.${cfg.secrets.scryptedEnv}.path ];
      volumes = [ "${state}/scrypted:/server/volume" ];
      ports = [ "127.0.0.1:${toString cfg.ports.scrypted}:10443/tcp" ];
      extraOptions = [ "--security-opt=no-new-privileges:true" ];
    };
  };
}
