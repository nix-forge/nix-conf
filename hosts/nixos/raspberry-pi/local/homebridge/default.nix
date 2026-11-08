{
  config,
  lib,
  pkgs,
  ...
}:
let
  network = builtins.fromJSON (builtins.readFile ../../../../shared/local/network.json);
  accessoryPorts = {
    start = 51827;
    end = 51828;
  };
in
{
  assertions = [
    {
      assertion =
        let
          ports = [
            config.services.homebridge.settings.bridge.port
          ]
          ++ lib.range accessoryPorts.start accessoryPorts.end;
          unscoped =
            config.networking.firewall.allowedTCPPorts
            ++ lib.attrByPath [ "eth0" "allowedTCPPorts" ] [ ] config.networking.firewall.interfaces;
        in
        lib.all (port: !builtins.elem port unscoped) ports;
      message = "Pi Homebridge HomeKit ports must remain source scoped by the host firewall.";
    }
  ];
  services.homebridge = {
    enable = true;
    openFirewall = false;
    settings.bridge = {
      name = "Homebridge";
      port = 51826;
      bind = [ "eth0" ];
      advertiser = "avahi";
    };
    settings.ports = accessoryPorts;
    managedUi = {
      enable = true;
      nodePackage = pkgs.nodejs;
      uiUsernameFile = config.nixSeal.secrets.homebridge-ui-username.path;
      uiPasswordFile = config.nixSeal.secrets.homebridge-ui-password.path;
    };
  };

  systemd.services.homebridge.requires = [ "nix-seal-activate.service" ];
  systemd.services.homebridge.after = [ "nix-seal-activate.service" ];

  networking.firewall.extraInputRules = lib.mkAfter ''
    iifname "eth0" ip saddr ${network.trustedLanCIDR} tcp dport { ${toString config.services.homebridge.settings.bridge.port}, ${toString accessoryPorts.start}-${toString accessoryPorts.end} } accept comment "Pi Homebridge HomeKit"
  '';
}
