{ config, lib, ... }:
let
  cfg = config.hardware.cpu.amd;
in
{
  options.hardware.cpu.amd = {
    enable = lib.mkEnableOption "Enable support for AMD CPUs.";
  };

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
