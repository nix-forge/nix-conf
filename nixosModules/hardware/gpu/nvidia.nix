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
    enable = lib.mkEnableOption ''
      Enable the Nvidia driver for desktops.
      This config is desgined for Turing or newer support.
    '';
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
    waylandEnvs = lib.mkEnableOption ''
      Enable Nvidia Wayland environment variables.
      This is useful for systems with primary GPU as Nvidia and uses Wayland.
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Base
      {
        # Enable Nvidia driver
        services.xserver.videoDrivers = [ "nvidia" ];

        # Enable hardware accelerated graphics driver
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
        };

        # Enable basic Nvidia options
        hardware.nvidia =
          let
            nvidiaPackage = config.hardware.nvidia.package;
          in
          {
            modesetting.enable = lib.mkDefault true;

            open = lib.mkOverride 990 (nvidiaPackage ? open && nvidiaPackage ? firmware);

            powerManagement.enable = true;
          };

        # blacklist nouveau module so that it does not conflict with nvidia drm
        boot.blacklistedKernelModules = [ "nouveau" ];

        # Extra packages for nvidia
        environment.systemPackages = with pkgs; [
          # GPU monitoring
          nvtopPackages.nvidia

          # vulkan
          vulkan-tools
          vulkan-loader
          vulkan-validation-layers
          vulkan-extension-layer
        ];
      }

      # Extra Mode Setting Config
      {
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
      }

      # Set the Nvidia Driver Package
      {
        hardware.nvidia.package =
          let
            nvidiaPkgs = config.boot.kernelPackages.nvidiaPackages;
            isNewer =
              version1: version2:
              if (builtins.compareVersions version1 version2) > 0 then true else false;
            chooseDriver =
              driver1: driver2:
              if (isNewer driver1.version driver2.version) then driver1 else driver2;

            inherit (nvidiaPkgs) beta;
            prod = nvidiaPkgs.production;

            nvidiaDriver = chooseDriver prod beta;
          in
          lib.mkIf cfg.betaDriver nvidiaDriver;
      }

      # Install Extra Packages for hardware acceleration with Nvidia VAAPI driver
      (lib.mkIf cfg.nvidia-vaapi-driver.enable {
        environment.sessionVariables = {
          LIBVA_DRIVER_NAME = "nvidia";
          MOZ_DISABLE_RDD_SANDBOX = "1"; # Firefox Support
        };

        hardware.graphics = {
          extraPackages = [ pkgs.nvidia-vaapi-driver ];
          extraPackages32 = [ pkgs.pkgsi686Linux.nvidia-vaapi-driver ];
        };

        environment.systemPackages = with pkgs; [
          libva
          libva-utils
        ];
      })

      # Nvidia Wayland Variables
      (lib.mkIf cfg.waylandEnvs {
        environment.sessionVariables = {
          GBM_BACKEND = "nvidia-drm"; # If you encounter crashes in Firefox then remove this line
          __GLX_VENDOR_LIBRARY_NAME = "nvidia"; # If you face problems with Discord windows not displaying or screen sharing not working in Zoom then remove this line
        };
      })

      # Fine-grained power management when using PRIME
      {
        # Experimental and only works on modern Nvidia GPUs (Turing or newer).
        # Requires Nvidia offload to be enabled.
        hardware.nvidia.powerManagement.finegrained =
          cfg.prime.offload.enable || cfg.prime.reverseSync.enable;
      }

      # Nvidia offload Command
      (lib.mkIf cfg.prime.offload.enable {
        # Rewrote `nvidia-offload` command to include more environment variables
        # Based NixOS Wiki: https://nixos.wiki/wiki/Nvidia
        # Aditional env var of LIBVA_DRIVER_NAME=nvidia due to nvidia-vaapi-driver
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "nvidia-offload" ''
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only
            export LIBVA_DRIVER_NAME=nvidia
            exec "$@"
          '')
        ];
      })

      # Nvidia for Docker Support
      { hardware.nvidia-container-toolkit.enable = true; }
    ]
  );
}
