{ self, ... }:
let
  moduleName = "custom";
in
{
  imports = [ (self.nixOSModules.networking { inherit moduleName; }) ];

  networking = {
    networkmanager = {
      enable = true;
      wifi.powersave = true;
    };

    enableIPv6 = true;

    ${moduleName} = {
      generateHostId = true;

      randomizeMacAddress = true;

      dnscrypt-proxy.enable = true;

      networkd-general.enable = true;
    };
  };
}
