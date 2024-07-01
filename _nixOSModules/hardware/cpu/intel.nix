{ config, lib, ... }:
let
  cfg = config.hardware.cpu.intel;
in
{
  options.hardware.cpu.intel = {
    enable = lib.mkEnableOption "Enable support for Intel CPUs.";
    iommu.enable = lib.mkEnableOption "Enable IOMMU support.";
    kvm = {
      enable = lib.mkEnableOption "Enable KVM support.";
      nestedVirtualization = lib.mkEnableOption "Enable nested virtualization.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    boot.kernelParams =
      [ ]
      ++ lib.optionals cfg.iommu.enable [
        "intel_iommu=on" # enable IOMMU support
        "iommu=pt" # prevent Linux from touching devices which cannot be passed through
      ]
      ++ lib.optionals cfg.kvm.enable [
        "kvm-intel" # enable KVM support
      ];

    boot.extraModprobeConfig = lib.mkIf (
      cfg.kvm.enable && cfg.kvm.nestedVirtualization
    ) "options kvm_amd nested=1";
  };
}
