{ config, lib, ... }:
let
  normalUsers = lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users;
  normalUserHomes = lib.mapAttrsToList (_: user: user.home) normalUsers;
  onAccessDirectories = lib.concatMap (home: [
    "${home}/Downloads"
    "${home}/Desktop"
  ]) normalUserHomes;
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

      # Real-time prevention covers each declared normal user's two ordinary
      # ingress surfaces. It is recursive and scans write/move events as well
      # as access events; monitoring full homes or / would exhaust inotify
      # watches, cause visible latency, and risk blocking vital files.
      OnAccessIncludePath = onAccessDirectories;
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
      Persistent = true;
      AccuracySec = "5m";
      RandomizedDelaySec = "30m";
    };

    clamdscan.timerConfig = {
      Persistent = true;
      AccuracySec = "1h";
      RandomizedDelaySec = "2h";
    };
  };
}
