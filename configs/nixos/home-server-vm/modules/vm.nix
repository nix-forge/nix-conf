{
  virtualisation.vmVariantWithBootLoader = {
    virtualisation = {
      memorySize = 8192;
      cores = 4;
      diskSize = 131072;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
        {
          from = "host";
          host.port = 8080;
          guest.port = 8080;
        }
      ];
    };
  };
}
