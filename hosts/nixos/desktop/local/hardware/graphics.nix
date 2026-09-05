{ config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  # Aquamarine separates AQ_DRM_DEVICES entries with colons, which makes the
  # standard PCI by-path name ambiguous. Give the RTX 4070's DRM card a stable
  # colon-free alias while leaving the kernel-assigned card number dynamic.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="0000:01:00.0", SYMLINK+="dri/desktop-nvidia-card"
  '';

  hardware = {
    # ddcutil needs i2c-dev and active-seat access to the GPU's DDC buses.
    # NixOS grants the latter with a narrow udev uaccess rule rather than a
    # permanently privileged group membership.
    i2c.enable = true;

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
