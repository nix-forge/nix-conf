{ lib, ... }:
let
  forwardPorts = [
    {
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }
    {
      from = "host";
      host.port = 8443;
      guest.port = 443;
    }
  ];

  vmConfig = {
    virtualisation = {
      memorySize = 8192;
      cores = 4;
      diskSize = 131072;
      useNixStoreImage = lib.mkForce true;
      mountHostNixStore = lib.mkForce false;
      sharedDirectories = lib.mkForce { };
      inherit forwardPorts;
    };
  };
in
{
  virtualisation.vmVariant = vmConfig;
  virtualisation.vmVariantWithBootLoader = vmConfig;
}
