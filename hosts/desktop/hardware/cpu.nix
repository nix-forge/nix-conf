{ inputs, lib, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-cpu-amd-zenpower
    inputs.nixos-hardware.nixosModules.common-cpu-amd-raphael-igpu

    inputs.ucodenix.nixosModules.default
  ];
  config = lib.mkMerge [
    {
      # Config for ucodenix
      # Set cpu model id for ucodenix flake
      services.ucodenix.cpuModelId = "00A60F12";
      boot.kernelParams = [ "microcode.amd_sha_check=off" ];
    }
    {
      # KVM
      boot.kernelParams = [ "kvm-amd" ];
      boot.extraModprobeConfig = "options kvm_amd nested=1";
    }
    {
      # IOMMU
      boot.kernelParams = [
        "amd_iommu=on" # enable IOMMU support
        "iommu=pt" # prevent Linux from touching devices which cannot be passed through
      ];
    }
  ];
}
