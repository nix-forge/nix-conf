{ self, ... }:
{
  imports = [
    self.nixOSModules.hardware.gpu.nvidia
    self.nixOSModules.hardware.gpu.intel
  ];

  hardware.nvidia = {
    enable = true;
    betaDriver = true;

    modesetting.enable = true;
    nvidiaSettings = true;

    prime = {
      offload.enable = true;
      nvidiaBusId = "PCI:01:00:0"; # card 0
      intelBusId = "PCI:00:02:0"; # card 1
    };

    # waylandEnvs = true;
    # nvidia-vaapi-driver.enable = true;
  };

  hardware.intelgpu.enable = true;
}
