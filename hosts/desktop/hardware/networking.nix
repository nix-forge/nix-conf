{ self, ... }:
let
  moduleName = "custom";
in
{
  imports = [ (self.nixosModules.networking { inherit moduleName; }) ];

  networking = {
    networkmanager.enable = false;

    enableIPv6 = true;

    ${moduleName} = {
      generateHostId = true;

      randomizeMacAddress = false;

      dnscrypt-proxy.enable = false;

      networkd-general.enable = true;
    };
  };
}
