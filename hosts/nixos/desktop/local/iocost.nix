{ config, ... }: {
  hardware.ioCost = {
    enable = true;
    kernelDevicePatterns = [ "nvme[0-9]*n[0-9]*" ];
    unitName = "desktop-iocost";
  };
  # This workstation gives foreground user work priority under contention.
  systemd.slices.user.sliceConfig.IOWeight = 200;
  system.build.desktopIOCostPolicy = config.system.build.ioCostPolicy;
}
