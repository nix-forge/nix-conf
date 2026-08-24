{ lib, ... }: {
  # Run Docker only through the unprivileged per-user daemon. Keeping the
  # rootful daemon off removes its root-equivalent socket and system service.
  virtualisation.docker = {
    enable = false;

    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # NixOS's rootless module installs a global user unit. Only start it for the
  # desktop account; `users.users.ianmh.linger` keeps it available after logout.
  systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce "ianmh";
}
