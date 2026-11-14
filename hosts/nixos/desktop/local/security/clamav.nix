{ config, lib, ... }:
let
  normalUsers = lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users;
  normalUserHomes = lib.mapAttrsToList (_: user: user.home) normalUsers;
  homeUsers = config.home-manager.users or { };
  onAccessDirectories = lib.concatLists (
    lib.mapAttrsToList (
      name: user:
      let
        directories = homeUsers.${name}.xdg.userDirs or { };
      in
      if directories.enable or false then
        lib.filter (path: path != null) [
          (directories.download or null)
          (directories.desktop or null)
        ]
      else
        [
          "${user.home}/Downloads"
          "${user.home}/Desktop"
        ]
    ) normalUsers
  );
  weeklyScanDirectories = normalUserHomes ++ [
    "/etc"
    "/tmp"
    "/var/lib"
    "/var/tmp"
  ];
in
{
  security.clamav.enable = true;

  services.clamav = {
    # FreshClam is the supported, signature-verified updater. Four-hourly
    # checks provide timely workstation coverage without needlessly polling
    # the public mirror; the timer is jittered below. Keep third-party feeds
    # off until their signing, maintenance, and false-positive behavior have
    # been reviewed for this desktop.
    updater = {
      frequency = 6;
      interval = "*-*-* 00/4:00:00";
      settings.NotifyClamd = "/etc/clamav/clamd.conf";
    };
    fangfrisch.enable = false;

    daemon.settings = {
      # The daemon never listens on TCP. Restrict its local socket to root and
      # the dedicated service account; scheduled scans use fd passing, so the
      # daemon does not need direct read access to personal files.
      LocalSocketMode = "660";

      # Four workers keep routine scans responsive on this 16-thread desktop
      # while leaving substantial foreground CPU capacity. The queue provides
      # bounded backpressure when scheduled and on-access scans overlap.
      MaxThreads = 4;
      MaxQueue = 8;

      # FreshClam can reload signatures while the long-running weekly scan is
      # active. Avoid temporarily retaining a second scanning engine on this
      # memory-constrained workstation; scans wait briefly for the reload.
      ConcurrentDatabaseReload = false;

      # Real-time prevention follows each declared normal user's selected XDG
      # ingress directories, with ordinary defaults for unmanaged accounts. It is recursive and scans write/move events as well
      # as access events; monitoring full homes or / would exhaust inotify
      # watches, cause visible latency, and risk blocking vital files.
      OnAccessIncludePath = lib.mkDefault onAccessDirectories;
      OnAccessPrevention = true;
      OnAccessExtraScanning = true;
    };

    clamonacc.enable = true;

    scanner = {
      # Scan every declared normal user's complete home weekly, which includes
      # every XDG user directory and any user-managed project, application, or
      # executable data. Include the mutable system locations from NixOS's
      # ClamAV baseline; exclude immutable Nix closures and pseudo-filesystems.
      # Downloads and Desktop additionally receive on-access prevention.
      interval = "Sun *-*-* 03:30:00";
      scanDirectories = weeklyScanDirectories;
    };
  };

  systemd.timers = {
    clamav-freshclam.timerConfig = {
      Persistent = false;
      AccuracySec = "5m";
      RandomizedDelaySec = "30m";
    };

    # An empty database must not wait for the calendar or its 30-minute
    # jitter. This independent timer also checks for updates after each boot.
    clamav-bootstrap = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        AccuracySec = "1s";
        RandomizedDelaySec = "15s";
        Unit = "clamav-freshclam.service";
      };
    };

    clamdscan.timerConfig = {
      Persistent = true;
      AccuracySec = "1h";
      RandomizedDelaySec = "2h";
    };
  };

  # Start scanning with the installed, verified database while FreshClam
  # updates independently. This workstation boots without waiting for Wi-Fi.
  # If the database is missing or invalid, clamd fails visibly and retries
  # until the updater has installed a usable database.
  systemd.services.clamav-daemon = {
    after = lib.mkForce [ ];
    wants = lib.mkForce [ ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  # Use the daemon's verified database without making every scheduled scan
  # wait for network access or starting another update transaction.
  systemd.services.clamdscan = {
    after = lib.mkForce [ "clamav-daemon.service" ];
    wants = lib.mkForce [ "clamav-daemon.service" ];
  };

  # This desktop deliberately does not block boot on Wi-Fi association.
  # FreshClam waits two minutes after boot, then retries if Wi-Fi or DNS is
  # still unavailable. A transient update failure should not leave the unit
  # degraded until the next scheduled interval.
  systemd.services.clamav-freshclam = {
    unitConfig = {
      StartLimitIntervalSec = "1h";
      StartLimitBurst = 12;
    };

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5min";
      TimeoutStartSec = "5min";
    };
  };
}
