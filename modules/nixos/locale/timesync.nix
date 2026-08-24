{ lib, ... }: {
  # Locale, timezone, keyboard layout, and clock-source geography describe a
  # host and belong in local/. Keep their management declarative so a desktop
  # session, TTY, and services agree after every rebuild.
  i18n.imperativeLocale = lib.mkDefault false;

  # Chrony is a disciplined NTP client with persistent clock-drift and RTC
  # calibration state. It is a better fit than systemd-timesyncd for a
  # workstation where accurate time affects TLS, package signatures, logs, and
  # scheduled tasks. Servers and whether they support NTS are host-local.
  services.chrony = {
    enable = lib.mkDefault true;
    serverOption = lib.mkDefault "iburst";
    enableMemoryLocking = lib.mkDefault true;
    enableRTCTrimming = lib.mkDefault true;
    makestep = {
      enable = lib.mkDefault true;
      threshold = lib.mkDefault 0.1;
      limit = lib.mkDefault 3;
    };

    # Chrony's Unix socket remains available to root and the chrony account.
    # Avoid even a loopback UDP command listener; this host is an NTP client,
    # not a time service for other machines.
    extraConfig = lib.mkAfter ''
      cmdport 0
    '';
  };
}
