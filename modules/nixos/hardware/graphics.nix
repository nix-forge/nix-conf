{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.graphics.acceleration;
in
{
  options.hardware.graphics.acceleration = {
    enable = lib.mkEnableOption "a hardware-acceleration baseline for graphical workloads";

    diagnostics.enable = lib.mkEnableOption "VA-API and Vulkan diagnostic tools" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Keep the baseline independent of a particular GPU vendor.  Vendor
    # drivers and any workload-specific device selection belong in the host's
    # local hardware configuration.
    hardware.graphics.enable = lib.mkDefault true;

    # These are small, read-only diagnostics that make it possible to verify
    # the actual driver and codec capabilities after a driver/kernel update.
    environment.systemPackages = lib.optionals cfg.diagnostics.enable [
      pkgs.libva-utils
      pkgs.vulkan-tools
    ];
  };
}
