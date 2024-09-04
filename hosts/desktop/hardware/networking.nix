{ self, ... }:
let
  moduleName = "custom";
in
{
  imports = [ (self.nixOSModules.networking { inherit moduleName; }) ];

  networking.${moduleName} = {
    generateHostId = true;

    randomizeMacAddress = false;

    dnscrypt-proxy.enable = true;

    networkd-general.enable = true;
  };
}
