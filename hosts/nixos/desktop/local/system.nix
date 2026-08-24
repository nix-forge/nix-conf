{ lib, ... }: {
  # This is an existing installation. Keep its original compatibility version;
  # it must never be raised to match the current nixpkgs release.
  system.stateVersion = "23.11";

  time.timeZone = "America/Los_Angeles";

  boot.loader.systemd-boot.enable = true;

  users.users.ianmh = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
    description = "Ian Holloway";
    # wheel is required for administration. GPU devices are granted through
    # logind/udev ACLs to the active graphical session; `uinput` is the narrow
    # additional permission Sunshine needs for virtual controller, keyboard,
    # and mouse input. Rootless Docker needs no root-equivalent docker group.
    extraGroups = [
      "wheel"
      "ianmh"
      "uinput"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf ianmh@Ians-MacBook-Pro.local"
    ];
  };

  # nix-seal gives the desktop user's runtime secrets a private matching group
  # without changing the account's existing primary group.
  users.groups.ianmh = { };

  # A NixOS deployment can execute arbitrary root activation code, so the
  # deploy credential is already root-equivalent. Authorize the MacBook key
  # directly for root instead of transmitting an interactive sudo password.
  # `restrict` removes interactive forwarding/agent/TTY capabilities from
  # this deployment-only root login; normal administration uses `ianmh`.
  users.users.root.openssh.authorizedKeys.keys = [
    "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3PjFNVCaBfwUJIKjQeBoK2kz0VaLdNAQVUb5pJdPPf ianmh@Ians-MacBook-Pro.local"
  ];

  services = {
    openssh.settings.AllowUsers = [
      "ianmh"
      "root"
    ];
    resolved.settings.Resolve = {
      # The desktop does not need to advertise itself through these legacy
      # discovery protocols. Keep .local resolution available without acting
      # as a responder, while removing LLMNR entirely.
      LLMNR = "false";
      MulticastDNS = "resolve";
    };
  };

  # Determinate Nixd is the Nix daemon on this host and owns garbage
  # collection. Do not run NixOS's legacy nix-gc timer alongside it.
  # This mirrors the automatic collection policy used on the MacBook.
  environment.etc."determinate/config.json".text = builtins.toJSON {
    garbageCollector.strategy = "automatic";
  };

  boot.loader.systemd-boot.configurationLimit = 12;

  # The rootless Docker module installs a global user unit.  Limit it to the
  # actual desktop user so GDM's greeter account does not repeatedly attempt
  # (and fail) to start a Docker daemon at the login screen.
  systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce "ianmh";
}
