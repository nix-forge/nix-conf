{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.security.clamav;
  daemonThreads = config.services.clamav.daemon.settings.MaxThreads;
  validDaemonThreads = builtins.isInt daemonThreads && daemonThreads > 0;
  scanWorkers = if validDaemonThreads then lib.min 4 daemonThreads else 1;
  scheduledScanner = pkgs.writers.writePython3Bin "clamav-scan-regular-files" {
    flakeIgnore = [ "E501" ];
  } ./clamav_scan.py;
in
{
  options.security.clamav.enable = lib.mkEnableOption ''
    the ClamAV signature-scanning baseline
  '';

  config = lib.mkIf cfg.enable {
    services.clamav = {
      # `clamd` keeps the verified signature database resident for inexpensive
      # local scans.  FreshClam maintains that database, and the scheduled
      # scanner uses the local Unix socket with fd passing rather than exposing
      # a network listener or granting the daemon access to every user file.
      daemon.enable = true;
      daemon.settings.MaxThreads = lib.mkDefault 4;
      updater.enable = true;
      scanner.enable = true;
    };

    assertions = [
      {
        assertion = validDaemonThreads;
        message = "security.clamav requires services.clamav.daemon.settings.MaxThreads to be a positive Nix integer.";
      }
      {
        assertion = config.services.clamav.daemon.enable;
        message = "security.clamav requires the clamd daemon.";
      }
      {
        assertion = config.services.clamav.updater.enable;
        message = "security.clamav requires FreshClam signature updates; a scanner without current signatures is not an acceptable baseline.";
      }
      {
        assertion = config.services.clamav.scanner.enable;
        message = "security.clamav requires a scheduled scanner; disable security.clamav instead of running an unmanaged partial setup.";
      }
      {
        assertion =
          !config.services.clamav.clamonacc.enable
          || (
            config.services.clamav.daemon.settings ? OnAccessIncludePath
            && (
              let
                paths = lib.toList config.services.clamav.daemon.settings.OnAccessIncludePath;
              in
              paths != [ ] && lib.all (path: builtins.isString path && lib.hasPrefix "/" path) paths
            )
          );
        message = "ClamAV on-access scanning requires nonempty absolute OnAccessIncludePath entries in host-local configuration.";
      }
    ];

    # The daemon and updater need no access to users' homes, devices, kernel
    # controls, or writable system paths. StateDirectory remains writable to
    # the service account under these restrictions. The scanner and optional
    # on-access monitor are separately constrained below because they must
    # inspect host files or use fanotify.
    systemd.services = {
      clamav-daemon.serviceConfig = {
        # The socket unit remains listening while the daemon stops or retries.
        # Removing its parent directory would unlink that live socket and leave
        # clients unable to connect after a successful daemon recovery.
        RuntimeDirectoryPreserve = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };

      clamav-freshclam.serviceConfig = {
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };

      # The scheduled scanner runs as root only to open files and pass their
      # descriptors to the unprivileged daemon. Keep its scan impact low and
      # remove network/device access; host-local configuration selects exactly
      # which data directories it may inspect.
      clamdscan.serviceConfig = {
        # Retain regular-file descriptors before submission. clamdscan's
        # pathname walk races cache eviction and reports special files as
        # errors. Remove the client when upstream offers these guarantees.
        ExecStart = lib.mkForce (
          utils.escapeSystemdExecArgs (
            [
              (lib.getExe scheduledScanner)
              "--workers"
              (toString scanWorkers)
              config.services.clamav.daemon.settings.LocalSocket
            ]
            ++ config.services.clamav.scanner.scanDirectories
          )
        );
        NoNewPrivileges = true;
        # The scan includes the host's temporary directories. A private /tmp
        # and /var/tmp would silently replace those inputs with empty trees.
        PrivateTmp = false;
        PrivateDevices = true;
        PrivateNetwork = true;
        ProtectSystem = "full";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        Nice = 19;
        IOSchedulingClass = "idle";
      };

      # clamonacc starts as root solely for fanotify permission events. Do not
      # enable it generically: the watched path, prevention mode, and latency
      # trade-off are host-local decisions.
      clamav-clamonacc.serviceConfig = lib.mkIf config.services.clamav.clamonacc.enable {
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        PrivateNetwork = true;
        ProtectSystem = "full";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
      };
    };

    # Do not enable third-party signature feeds or configure PUA/encrypted-file
    # alerts in this shared baseline. They materially alter false-positive
    # behavior and, with on-access prevention, can block legitimate work. A
    # host may add a separately reviewed feed or policy locally.
  };
}
