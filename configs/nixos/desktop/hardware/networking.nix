{ self, ... }:
{
  imports = [ self.nixosModules.networking ];

  networking = {
    networkmanager.enable = false;

    enableIPv6 = true;

    extras = {
      generateHostId = true;

      randomizeMacAddress = false;

      dnscrypt-proxy.enable = false;

      networkd-general.enable = true;
    };
  };
}
