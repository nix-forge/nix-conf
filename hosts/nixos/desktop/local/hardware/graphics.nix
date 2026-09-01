{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics = {
      enable = true;
      acceleration.enable = true;
      # Required by 32-bit Vulkan/OpenGL applications such as many games.
      enable32Bit = true;
    };

    # Mesa supplies the native radeonsi VA-API driver for the Raphael iGPU.
    # NixOS's NVIDIA module supplies nvidia-vaapi-driver when this is enabled;
    # its direct NVDEC backend was verified on this RTX 4070.  Do not set a
    # global LIBVA_DRIVER_NAME: that would make one GPU invisible to apps that
    # are better served by the other.
    amdgpu.initrd.enable = true;
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      videoAcceleration = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };
  };
}
