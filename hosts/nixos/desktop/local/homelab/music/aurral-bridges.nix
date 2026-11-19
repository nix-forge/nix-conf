{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.desktopAurral;
  httpPort = toString cfg.httpPort;
  lidarrPort = toString config.services.lidarr.settings.server.port;
  namespace = config.homelab.vpn.namespace.name;
  bridgeDirectory = "/run/aurral-network";
  bridge =
    confined: upstreamUnits: command:
    let
      prerequisites = [ "systemd-tmpfiles-setup.service" ] ++ upstreamUnits;
    in
    {
      requires = prerequisites;
      after = prerequisites;
      vpn = lib.optionalAttrs confined {
        enable = true;
        inherit namespace;
        extraAddressFamilies = [ "AF_UNIX" ];
      };
      serviceConfig = {
        User = "aurral";
        Group = "aurral";
        ExecStart = "${lib.getExe pkgs.socat} ${command}";
        Restart = "on-failure";
        RestartSec = "2s";
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = [ ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
        IPAddressDeny = [ "any" ];
        IPAddressAllow = [ "127.0.0.0/8" ];
        ReadWritePaths = [ bridgeDirectory ];
        TasksMax = 128;
        MemoryMax = "128M";
      };
    };
in
{
  options.homelab.desktopAurral.httpPort = lib.mkOption {
    type = lib.types.ints.between 1024 65535;
    default = 3001;
    description = "Unprivileged loopback HTTP port used by Aurral and its host-side bridge.";
  };
  options.homelab.desktopAurral.backendUrl = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    internal = true;
    default = "http://127.0.0.1:${toString config.homelab.desktopAurral.httpPort}";
    description = "Loopback URL used by host services to reach Aurral through its bridge.";
  };

  config = {
    # Unix sockets keep the host and VPN loopback endpoints reachable without
    # giving the VPN namespace a route into the host network.
    systemd.tmpfiles.rules = [ "d ${bridgeDirectory} 0700 aurral aurral -" ];
    systemd.services = {
      aurral-lidarr-host =
        bridge false [ ]
          "UNIX-LISTEN:${bridgeDirectory}/lidarr.sock,fork,unlink-early TCP:127.0.0.1:${lidarrPort}";
      aurral-lidarr-vpn =
        bridge true [ "aurral-lidarr-host.service" ]
          "TCP-LISTEN:${lidarrPort},bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:${bridgeDirectory}/lidarr.sock";
      aurral-http-vpn = bridge true [
        "aurral.service"
      ] "UNIX-LISTEN:${bridgeDirectory}/http.sock,fork,unlink-early TCP:127.0.0.1:${httpPort}";
      aurral-http-host =
        bridge false [
          "aurral-http-vpn.service"
        ] "TCP-LISTEN:${httpPort},bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:${bridgeDirectory}/http.sock"
        // {
          wantedBy = [ "multi-user.target" ];
        };
    };

    assertions = [
      {
        assertion = cfg.httpPort != config.services.lidarr.settings.server.port;
        message = "Aurral and its Lidarr bridge need distinct loopback ports.";
      }
      {
        assertion =
          lib.all
            (
              unitName:
              let
                unit = config.systemd.services.${unitName};
              in
              unit.vpn.enable
              && unit.vpn.namespace == namespace
              && unit.serviceConfig.NetworkNamespacePath == "/run/netns/${namespace}"
            )
            [
              "aurral-http-vpn"
              "aurral-lidarr-vpn"
            ]
          &&
            lib.all
              (
                unitName:
                let
                  serviceConfig = config.systemd.services.${unitName}.serviceConfig;
                in
                serviceConfig.IPAddressDeny == [ "any" ] && serviceConfig.IPAddressAllow == [ "127.0.0.0/8" ]
              )
              [
                "aurral-http-host"
                "aurral-lidarr-host"
              ];
        message = "Aurral API bridges must preserve VPN confinement and loopback-only host access.";
      }
    ];
  };
}
