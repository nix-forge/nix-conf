_: {
  # Run Docker only through the unprivileged per-user daemon. Keeping the
  # rootful daemon off removes its root-equivalent socket and system service.
  virtualisation.docker = {
    enable = false;

    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # NixOS's rootless module installs a global user unit.  The eligible account
  # is a host-local decision; set ConditionUser under the host's local/ policy
  # so another desktop or multi-user system does not inherit `ianmh`.
}
