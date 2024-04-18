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
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm"; # If you encounter crashes in Firefox then remove this line
    __GLX_VENDOR_LIBRARY_NAME = "nvidia"; # If you face problems with Discord windows not displaying or screen sharing not working in Zoom then remove this line
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}
