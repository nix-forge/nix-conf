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

  # AMD GPU
  services.xserver.videoDrivers = [ "modesetting" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  hardware.amdgpu = {
    initrd.enable = true;

    opencl.enable = true;

    amdvlk = {
      enable = true;
      support32Bit.enable = true;
      supportExperimental.enable = true;
    };
  };
}
