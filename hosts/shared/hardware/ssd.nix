{
  services.fstrim = {
    # We may enable this unconditionally across all systems because it's performance
    # impact is negligible on systems without a SSD - which means it's a no-op with
    # almost no downsides aside from the service firing once per week.
    enable = true;

    # The timer interval passed to the systemd service. The default is monthly
    # but we prefer trimming weekly as the system receives a lot of writes.
    interval = "weekly";
  };

  # Tweak fstrim service to run only when on AC power
  # and to be nice to other processes. This is a generally
  # a good idea for any service that runs periodically to
  # save power and avoid locking down the system in an
  # unexpected manner, e.g., while working on something else.
  systemd.services.fstrim = {
    unitConfig.ConditionACPower = true;

    serviceConfig = {
      Nice = 19; # lowest priority, be nice to other processes
      IOSchedulingClass = "idle";
    };
  };
}
