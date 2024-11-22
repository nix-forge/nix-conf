{ self, ... }:
{
  imports = [ self.nixOSModules.hardware.gpu.nvidia ];

  hardware.nvidia = {
    enable = true;
    betaDriver = true;

    modesetting.enable = true;
    nvidiaSettings = true;

    # prime = {
    #   offload.enable = true;
    #   amdgpuBusId = "PCI:01:00:0"; # card 0
    #   nvidiaBusId = "PCI:10:00:0"; # card 1
    # };

    # waylandEnvs = true;
    # nvidia-vaapi-driver.enable = true;
  };

  hardware.intelgpu.enable = true;
}
