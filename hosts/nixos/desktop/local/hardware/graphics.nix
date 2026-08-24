{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics = {
      enable = true;
      # Required by 32-bit Vulkan/OpenGL applications such as many games.
      enable32Bit = true;
    };
    amdgpu.initrd.enable = true;
    nvidia = {
      modesetting.enable = true;
      open = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };
  };
}
