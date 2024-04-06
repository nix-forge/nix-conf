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

    # Nvidia VAAPI driver direct backend
    environment.sessionVariables.NVD_BACKEND = lib.mkIf cfg.nvidia-vaapi-driver.directBackend "direct";

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
