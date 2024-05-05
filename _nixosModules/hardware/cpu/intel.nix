{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.cpu.intel;
in {
  options.hardware.cpu.intel = {
    enable = lib.mkEnableOption "Enable support for Intel CPUs.";
    iommu = lib.mkEnableOption "Enable IOMMU support.";
  };

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    boot.kernelParams = lib.mkIf cfg.iommu [
      "intel_iommu=on" # enable IOMMU support
      "iommu=pt" # prevent Linux from touching devices which cannot be passed through
    ];
  };
}
