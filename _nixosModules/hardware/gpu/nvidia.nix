{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  cfg = config.hardware.nvidia;
in
{
  options.hardware.nvidia = {
    enable = lib.mkEnableOption "Enable the Nvidia driver for desktops.";
    nvidia-vaapi-driver = {
      enable = lib.mkEnableOption (
        lib.mdDoc ''
          Enable the nvidia-vaapi-driver.
          https://github.com/elFarto/nvidia-vaapi-driver
        ''
      );
      directBackend = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Use the direct backend for nvidia-vaapi-driver.";
      };
    };
    betaDriver = lib.mkEnableOption (
      lib.mdDoc ''
        Enable the beta nvidia driver.
        This will choose the latest driver version available between the production and beta drivers.
      ''
    );
    earlyLoading = lib.mkEnableOption (
      lib.mdDoc ''
        Enable early loading of the Nvidia driver.
        This is useful for systems with Nvidia GPUs that are not the primary GPU.
      ''
    );
    waylandEnvs = lib.mkEnableOption (
      lib.mdDoc ''
        Enable Nvidia Wayland environment variables.
        This is useful for systems with primary GPU as Nvidia and uses Wayland.
      ''
    );
  };

  config = lib.mkIf cfg.enable {
    # Enable Nvidia driver
    services.xserver.videoDrivers = [ "nvidia" ];

    # Nvidia VAAPI driver
    hardware.opengl = lib.mkMerge [
      {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
      }

      (lib.mkIf cfg.nvidia-vaapi-driver.enable {
        extraPackages = [
          pkgs.nvidia-vaapi-driver
        ] ++ lib.optionals (pkgs ? ffmpeg-full) [ pkgs.ffmpeg-full ];
        extraPackages32 = [ pkgs.pkgsi686Linux.nvidia-vaapi-driver ];
      })
    ];

    environment.sessionVariables = lib.mkMerge [
      { NVD_BACKEND = lib.mkIf cfg.nvidia-vaapi-driver.directBackend "direct"; }

      (lib.mkIf cfg.waylandEnvs {
        LIBVA_DRIVER_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm"; # If you encounter crashes in Firefox then remove this line
        __GLX_VENDOR_LIBRARY_NAME = "nvidia"; # If you face problems with Discord windows not displaying or screen sharing not working in Zoom then remove this line
        WLR_NO_HARDWARE_CURSORS = "1";
        XDG_SESSION_TYPE = "wayland";
      })
    ];

    # Nvidia beta driver
    hardware.nvidia.package =
      let
        nvidiaPkgs = config.boot.kernelPackages.nvidiaPackages;
        beta = nvidiaPkgs.beta;
        prod = nvidiaPkgs.production;
        nvidiaDriver = if (lib.versionOlder beta.version prod.version) then prod else beta;
      in
      lib.mkIf cfg.betaDriver nvidiaDriver;

    # Extra Mode Setting Config
    # Nvidia DRM (Direct Rendering Manager) KMS (Kernel Mode Setting) support
    # Based on Arch Wiki: <https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting>
    # NOTE: The kernel patameters for Nvidia use "-" instead of "_" which the Nvidia kernel modules use
    boot.kernelParams = lib.mkIf config.hardware.nvidia.modesetting.enable [ "nvidia-drm.fbdev=1" ];

    # Early loading support for Nvidia
    # Also Based on Arch Wiki: https://wiki.archlinux.org/title/NVIDIA#Early_loading
    # NOTE: VA-API will not work if Nvidia module "nvidia_uvm" is not loaded.
    boot.initrd.kernelModules = lib.mkIf config.hardware.nvidia.earlyLoading [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];
  };
}
