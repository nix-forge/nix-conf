{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.amdgpu;
in
{
  options.hardware.amdgpu = {
    enable = lib.mkEnableOption "Enable amdgpu support";

    loadInInitrd =
      lib.mkEnableOption (
        lib.mdDoc "loading `amdgpu` kernelModule at stage 1. (Add `amdgpu` to `boot.initrd.kernelModules`)"
      )
      // {
        default = true;
      };

    opencl =
      lib.mkEnableOption (
        lib.mdDoc "rocm opencl runtime (Install rocmPackages.clr and rocmPackages.clr.icd)"
      )
      // {
        default = true;
      };
  };

  config = lib.mkIf cfg.enable {
    services.xserver.videoDrivers = [
      "amdgpu"
      "modesetting"
    ];

    hardware.opengl = lib.mkMerge [
      {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
      }

      (lib.mkIf cfg.opencl {
        extraPackages =
          if pkgs ? rocmPackages.clr then
            with pkgs.rocmPackages;
            [
              clr
              clr.icd
            ]
          else
            with pkgs;
            [
              rocm-opencl-icd
              rocm-opencl-runtime
            ];
      })
    ];

    boot.initrd.kernelModules = lib.mkIf cfg.loadInInitrd [ "amdgpu" ];

    boot.kernelParams = [
      # Ensure that AMDGPU is loaded over Radeon.
      "amdgpu"

      # for Southern Islands (SI i.e. GCN 1) cards
      "radeon.si_support=0"
      "amdgpu.si_support=1"
      # for Sea Islands (CIK i.e. GCN 2) cards
      "radeon.cik_support=0"
      "amdgpu.cik_support=1"

      # Allow the GPU to power down when displays are attached.
      "amdgpu.runpm=-2"
    ];
  };
}
