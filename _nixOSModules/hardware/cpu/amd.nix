{ config, lib, ... }:
let
  cfg = config.hardware.cpu.amd;
in
{
  options.hardware.cpu.amd = {
    enable = lib.mkEnableOption "Enable support for AMD CPUs.";
    iommu = lib.mkEnableOption "Enable IOMMU support.";
  };

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    boot.kernelParams = lib.mkIf cfg.iommu [
      "amd_iommu=on" # enable IOMMU support
      "iommu=pt" # prevent Linux from touching devices which cannot be passed through
    ];
  };
}
