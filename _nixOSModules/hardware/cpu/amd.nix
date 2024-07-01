{ config, lib, ... }:
let
  cfg = config.hardware.cpu.amd;
in
{
  options.hardware.cpu.amd = {
    enable = lib.mkEnableOption "Enable support for AMD CPUs.";
    iommu.enable = lib.mkEnableOption "Enable IOMMU support.";
    kvm = {
      enable = lib.mkEnableOption "Enable KVM support.";
      nestedVirtualization = lib.mkEnableOption "Enable nested virtualization.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    boot.kernelParams =
      [
        "amd-pstate" # load pstate module in case the device has a newer gpu
        "zenpower" # zenpower is for reading cpu info, i.e voltage
        "msr" # x86 CPU MSR access device
      ]
      ++ lib.optionals cfg.iommu.enable [
        "amd_iommu=on" # enable IOMMU support
        "iommu=pt" # prevent Linux from touching devices which cannot be passed through
      ]
      ++ lib.optionals cfg.kvm.enable [
        "kvm-amd" # enable KVM support
      ];

    boot.extraModprobeConfig = lib.mkIf (
      cfg.kvm.enable && cfg.kvm.nestedVirtualization
    ) "options kvm_amd nested=1";

  };
}
