{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.nvidia;
in
{
  options.hardware.nvidia = {
    enable = lib.mkEnableOption "Enable the Nvidia driver for desktops.";
    nvidia-vaapi-driver = {
      enable = lib.mkEnableOption ''
        Enable the nvidia-vaapi-driver.
        https://github.com/elFarto/nvidia-vaapi-driver
      '';
    };
    betaDriver = lib.mkEnableOption ''
      Enable the beta nvidia driver.
      This will choose the latest driver version available between the production and beta drivers.
    '';
    earlyLoading = lib.mkEnableOption ''
      Enable early loading of the Nvidia driver.
      This is useful for systems with Nvidia GPUs that are not the primary GPU.
    '';
    waylandEnvs = lib.mkEnableOption ''
      Enable Nvidia Wayland environment variables.
      This is useful for systems with primary GPU as Nvidia and uses Wayland.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Enable Nvidia driver
    services.xserver.videoDrivers = [ "nvidia" ];

    # Nvidia VAAPI driver
    hardware.graphics = lib.mkMerge [
      { enable = true; }

      (lib.mkIf cfg.nvidia-vaapi-driver.enable {
        extraPackages = [ pkgs.nvidia-vaapi-driver ];
        extraPackages32 = [ pkgs.pkgsi686Linux.nvidia-vaapi-driver ];
      })
    ];

    environment.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.nvidia-vaapi-driver.enable {
        MOZ_DISABLE_RDD_SANDBOX = "1";
        LIBVA_DRIVER_NAME = "nvidia";
      })

      (lib.mkIf cfg.waylandEnvs {
        GBM_BACKEND = "nvidia-drm"; # If you encounter crashes in Firefox then remove this line
        __GLX_VENDOR_LIBRARY_NAME = "nvidia"; # If you face problems with Discord windows not displaying or screen sharing not working in Zoom then remove this line
        XDG_SESSION_TYPE = "wayland";
      })
    ];

    # Nvidia beta driver
    hardware.nvidia.package =
      let
        nvidiaPkgs = config.boot.kernelPackages.nvidiaPackages;
        isNewer =
          version1: version2: if (builtins.compareVersions version1 version2) > 0 then true else false;
        chooseDriver =
          driver1: driver2: if (isNewer driver1.version driver2.version) then driver1 else driver2;
      in
      let
        beta = nvidiaPkgs.beta;
        prod = nvidiaPkgs.production;

        nvidiaDriver = chooseDriver prod beta;
      in
      lib.mkIf cfg.betaDriver nvidiaDriver;

    # Extra Mode Setting Config
    # Nvidia DRM (Direct Rendering Manager) KMS (Kernel Mode Setting) support
    # Based on Arch Wiki: <https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting>
    # NOTE: The kernel patameters for Nvidia use "-" instead of "_" which the Nvidia kernel modules use
    #       However, we will use both just in case.
    boot.kernelParams = lib.mkIf cfg.modesetting.enable [
      "nvidia-drm.modeset=1"
      "nvidia_drm.modeset=1"

      "nvidia-drm.fbdev=1"
      "nvidia_drm.fbdev=1"
    ];

    # Early loading support for Nvidia
    # Also Based on Arch Wiki: https://wiki.archlinux.org/title/NVIDIA#Early_loading
    # NOTE: VA-API will not work if Nvidia module "nvidia_uvm" is not loaded.
    boot.initrd.kernelModules = lib.mkIf cfg.earlyLoading [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];

    # blacklist nouveau module so that it does not conflict with nvidia drm
    boot.blacklistedKernelModules = [ "nouveau" ];

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    # Requires Nvidia offload to be enabled.
    hardware.nvidia.powerManagement.finegrained =
      cfg.prime.offload.enable || cfg.prime.reverseSync.enable;

    # Nvidia offload
    environment.systemPackages =
      (with pkgs; [
        nvtopPackages.nvidia

        # mesa
        mesa

        # vulkan
        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
        vulkan-extension-layer

      ])
      ++ lib.optionals (cfg.nvidia-vaapi-driver.enable) (
        with pkgs;
        [
          # libva
          libva
          libva-utils
        ]
      )
      # Rewrote `nvidia-offload` command to include more environment variables
      # Based NixOS Wiki: https://nixos.wiki/wiki/Nvidia
      # Aditional env var of LIBVA_DRIVER_NAME=nvidia due to nvidia-vaapi-driver
      ++ lib.optionals (cfg.prime.offload.enable) [
        (pkgs.writeShellScriptBin "nvidia-offload" ''
          export __NV_PRIME_RENDER_OFFLOAD=1
          export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
          export __GLX_VENDOR_LIBRARY_NAME=nvidia
          export __VK_LAYER_NV_optimus=NVIDIA_only
          export LIBVA_DRIVER_NAME=nvidia
          exec "$@"
        '')
      ];
  };
}
