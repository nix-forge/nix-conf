{
  config,
  lib,
  pkgs,
  ...
}:
{
  # nct6683 only monitors this MSI board; its PWM attributes are read-only.
  # The dedicated driver exposes controls and restores BIOS mode on unload.
  # Keep a single driver owning the Super-I/O registers.
  boot.blacklistedKernelModules = [ "nct6683" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nct6687d ];
  boot.kernelModules = [ "nct6687" ];

  programs.coolercontrol.enable = true;

  # CoolerControl edits its own device IDs, calibration and profiles. Store
  # these in persistent service state, seeded once, rather than an immutable
  # /etc file. Retain the packaged notify/watchdog/shutdown behavior.
  systemd.services.coolercontrold = {
    after = [ "systemd-modules-load.service" ];
    environment.CC_CONFIG_DIR = "/var/lib/coolercontrol";
    serviceConfig = {
      StateDirectory = "coolercontrol";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    preStart = ''
      if [ ! -e /var/lib/coolercontrol/config.toml ]; then
        ${lib.getExe' pkgs.coreutils "install"} -m 0600 ${./fans.toml} /var/lib/coolercontrol/config.toml
      fi
    '';
  };
}
