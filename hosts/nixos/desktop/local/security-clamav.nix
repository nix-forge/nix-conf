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

      # Real-time prevention is deliberately restricted to the untrusted file
      # ingress directory. It is recursive and scans write/move events as
      # well as access events; expanding this to /home or / risks exhausting
      # inotify watches, causing visible latency, or blocking vital files.
      OnAccessIncludePath = [ "/home/ianmh/Downloads" ];
      OnAccessPrevention = true;
      OnAccessExtraScanning = true;
    };

    clamonacc.enable = true;

    scanner = {
      # Scan persistent user content weekly during an idle period. Excluding
      # Nix closures, container layers, caches, and the large games subvolume
      # prevents redundant I/O and avoids disrupting the desktop; Downloads
      # receives both this scan and on-access prevention.
      interval = "Sun *-*-* 03:30:00";
      scanDirectories = [
        "/home/ianmh/Downloads"
        "/home/ianmh/Desktop"
        "/home/ianmh/Documents"
        "/home/ianmh/Projects"
      ];
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
