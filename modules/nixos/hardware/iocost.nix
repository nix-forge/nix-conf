{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.ioCost;
  enable = pkgs.writeShellScript "enable-iocost" (
    (import ../../../lib/templates/text.nix) ./iocost-assets/enable.sh {
      cgroupRoot = lib.escapeShellArg "/sys/fs/cgroup";
    }
  );
  rules = lib.concatMapStringsSep "\n" (pattern: ''
    ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", KERNEL=="${pattern}", ENV{IOCOST_SOLUTIONS}=="", RUN+="${enable} %M:%m"
  '') cfg.kernelDevicePatterns;
in
{
  key = "nix-conf/iocost/nixos";
  options.hardware.ioCost = {
    enable = lib.mkEnableOption "kernel-adaptive proportional I/O cost control";
    kernelDevicePatterns = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      example = [ "nvme[0-9]*n[0-9]*" ];
      description = "Whole-disk kernel name globs to manage when no hwdb or manually measured policy is present.";
    };
    unitName = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*";
      default = "adaptive-iocost";
      description = "Systemd service identifier, without the .service suffix.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.kernelDevicePatterns != [ ]
          && lib.all (
            pattern: builtins.match "([-A-Za-z0-9*?_]|[[][0-9A-Za-z-]+[]])+" pattern != null
          ) cfg.kernelDevicePatterns;
        message = "hardware.ioCost requires explicit, safe kernel-device glob patterns.";
      }
    ];
    services.udev.extraRules = rules;
    systemd.services.${cfg.unitName} = {
      description = "Enable kernel-adaptive I/O sharing on selected disks";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-udev-trigger.service"
      ];
      before = [ "nix-daemon.service" ];
      path = [
        pkgs.coreutils
        config.systemd.package
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = (import ../../../lib/templates/text.nix) ./iocost-assets/reconcile.sh {
        inherit enable;
        patterns = lib.escapeShellArgs cfg.kernelDevicePatterns;
      };
    };
    system.build.ioCostPolicy = pkgs.linkFarm "iocost-policy" [
      {
        name = "enable";
        path = enable;
      }
      {
        name = "${cfg.unitName}.service";
        path = "${config.systemd.units."${cfg.unitName}.service".unit}/${cfg.unitName}.service";
      }
      {
        name = "udev.rules";
        path = pkgs.writeText "iocost-udev.rules" rules;
      }
    ];
  };
}
