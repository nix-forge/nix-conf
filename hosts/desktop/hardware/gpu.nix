{ self, ... }:
{
  imports = [
    self.nixosModules.hardware.gpu.nvidia
    self.nixosModules.hardware.gpu.amd
  ];

  hardware.nvidia = {
    enable = true;
    betaDriver = true;

    modesetting.enable = true;
    open = true;

    nvidia-vaapi-driver = {
      enable = true;
      directBackend = true;
    };

    earlyLoading = true;

    nvidiaSettings = true;

    # prime = {
    #   offload.enable = true;
    #   amdgpuBusId = "PCI:01:00:0"; # card 0
    #   nvidiaBusId = "PCI:10:00:0"; # card 1
    # };

    waylandEnvs = true;
  };

  # hardware.amdgpu = {
  #   enable = true;
  #   amdvlk = true;
  # };
}
