{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.nixos-hardware.nixosModules.common-gpu-nvidia ];
  config = lib.mkMerge [
    {
      services.xserver.videoDrivers = [ "nvidia" ];
      boot.blacklistedKernelModules = [ "nouveau" ];
      hardware.nvidia = {
        modesetting.enable = true;
        nvidiaSettings = true;

        prime = {
          amdgpuBusId = "PCI:01:00:0"; # card 0
          nvidiaBusId = "PCI:10:00:0"; # card 1
        };

        videoAcceleration = true;

        open = true;

        package =
          let
            nvidiaPkgs = config.boot.kernelPackages.nvidiaPackages;
            isNewer =
              version1: version2: if (builtins.compareVersions version1 version2) > 0 then true else false;
            chooseDriver =
              driver1: driver2: if (isNewer driver1.version driver2.version) then driver1 else driver2;

            inherit (nvidiaPkgs) beta;
            prod = nvidiaPkgs.production;

            nvidiaDriver = chooseDriver prod beta;
          in
          nvidiaDriver;
      };
      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        MOZ_DISABLE_RDD_SANDBOX = "1"; # Firefox Support
      };
      environment.systemPackages = with pkgs; [
        # GPU monitoring
        nvtopPackages.nvidia

        # vulkan
        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
        vulkan-extension-layer
      ];
      hardware.nvidia-container-toolkit.enable = true;
    }
    {
      # AMD GPU
      services.xserver.videoDrivers = [ "amdgpu" ];
      hardware.graphics = {
        enable = true;
      };
      hardware.amdgpu = {
        initrd.enable = true;
        opencl.enable = true;
      };
    }
  ];
}
