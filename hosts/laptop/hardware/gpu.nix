{ self, config, ... }:
{
  imports = [
    self.nixosModules.hardware.gpu.nvidia
    self.nixosModules.hardware.gpu.intel
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

    prime = {
      offload.enable = true;
      intelBusId = "PCI:0:2:0"; # card 0
      nvidiaBusId = "PCI:1:0:0"; # card 1
    };

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    powerManagement.enable = true;
    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    # Requires Nvidia offload to be enabled.
    powerManagement.finegrained =
      config.hardware.nvidia.prime.offload.enable || config.hardware.nvidia.prime.reverseSync.enable;
  };

  hardware.intelgpu = {
    enable = true;
    guc = true;
    huc = true;
  };
}
