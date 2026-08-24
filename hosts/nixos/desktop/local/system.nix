{
  config,
  lib,
  pkgs,
  ...
}:
{
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0S5mEDZaqHcYsDLQLWqqG6wrz9IJOH5R9OhNHgk9Rw bh@Holloway-Mac-mini.local"
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
    openssh.settings = {
      AllowUsers = [
        "ianmh"
        "root"
      ];

      # This desktop is administered over SSH but never used as an X11 jump
      # host.  DNS lookups during authentication are both unnecessary on the
      # LAN and a common source of delayed logins; stale Unix sockets should
      # not prevent a new SSH connection from starting either.
      X11Forwarding = false;
      UseDns = false;
      StreamLocalBindUnlink = true;
    };
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

  # `nh` is the local interface for building and activating this host.  Keep
  # its flake path unset: the checkout may live on a different filesystem on
  # the desktop than it does on the MacBook.  From a checkout, use
  # `nh os switch . -H desktop`.  deploy-rs remains the remote deployment path,
  # because its activation protocol supplies the connectivity rollback guard.
  programs.nh.enable = true;

  # Determinate Nix owns automatic garbage collection on this host, so do not
  # enable nh's clean timer as a competing collector.

  # Show a generation diff before activation and reject a closure intended for
  # another host.  Unlike SRVOS's interactive hostname prompt, fail cleanly so
  # deploy-rs does not hang during a non-interactive remote deployment.  Set
  # EXPECTED_HOSTNAME=desktop only for an intentional hostname migration.
  system.preSwitchChecks = {
    updateDiff = ''
      incoming="''${1-}"
      if [[ -e /run/current-system && -n "$incoming" ]]; then
        echo "--- diff to current system"
        ${pkgs.nvd}/bin/nvd diff /run/current-system "$incoming"
        echo "---"
      fi
    '';

    expectedHostname = ''
      actual="$(< /proc/sys/kernel/hostname)"
      expected="${config.networking.hostName}"
      if [[ -e /run/booted-system && "$actual" != "$expected" && "''${EXPECTED_HOSTNAME:-}" != "$expected" ]]; then
        echo "refusing to activate '$expected' on host '$actual'" >&2
        echo "set EXPECTED_HOSTNAME='$expected' only for an intentional hostname migration" >&2
        exit 1
      fi
    '';
  };

  # The rootless Docker module installs a global user unit.  Limit it to the
  # actual desktop user so GDM's greeter account does not repeatedly attempt
  # (and fail) to start a Docker daemon at the login screen.
  systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce "ianmh";
}
