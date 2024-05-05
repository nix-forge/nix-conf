{ self, ... }:
{
  imports = [ self.nixosModules.hardware.gpu.nvidia ];

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

    waylandEnvs = true;
  };
}
