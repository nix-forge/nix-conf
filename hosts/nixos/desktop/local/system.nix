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

  # Region and language are properties of this workstation. Keep the RTC in
  # UTC: it is robust across daylight-saving transitions and avoids making the
  # firmware clock depend on the configured display timezone. If this machine
  # continues to boot native Windows, configure that installation for UTC too.
  time = {
    timeZone = "America/Los_Angeles";
    hardwareClockInLocalTime = false;
  };
  i18n.defaultLocale = "en_US.UTF-8";

  # This desktop uses the established GNOME Keyring Secret Service and GCR SSH
  # agent. Keep OpenSSH's legacy agent off so applications have one predictable
  # SSH_AUTH_SOCK; a future oo7 migration must first back up and test the
  # existing login keyring because its migration is one-way.
  security.desktopKeyring.enable = true;
  programs.ssh.startAgent = false;

  # This password-based greetd stack includes PAM's `login` service. Reject
  # null-password accounts despite the permissive shadow-program default,
  # retain a short failure delay against rapid local guessing, and show the
  # most recent successful login for basic user-visible auditing. `su` is
  # intentionally limited to wheel administrators; remote SSH passwords are
  # already disabled in the SSH policy. Do not enable pam_gnupg: this account
  # has no managed private-key/keygrip preset configuration to unlock.
  security.pam.services = {
    login = {
      allowNullPassword = lib.mkForce false;
      failDelay = {
        enable = true;
        delay = 3000000;
      };
      lastlog = {
        enable = true;
        silent = false;
      };
      gnupg.enable = false;
    };
    su.requireWheel = true;
  };

  # NTS authenticates time received over NTP. Use two independent public
  # providers instead of an NTP pool: NTS cannot safely be assumed for a pool
  # member, and Cloudflare's anycast endpoint keeps latency low on this US
  # desktop while Netnod supplies an independent trust domain.
  services.chrony = {
    enableNTS = true;
    servers = [
      "time.cloudflare.com"
      "nts.netnod.se"
    ];
  };

  # Firmware mode and NVRAM ownership are properties of this physical host.
  # Shared boot modules only add policy after a host selects its loader.
  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  # This desktop's ESP is 1 GiB.  Reserve enough space for systemd-boot
  # generations and a safely staged firmware capsule; a firmware update will
  # fail closed rather than crowd the ESP.  Capsule delivery remains fwupd's
  # vendor-detected default, while MSI BIOS images continue to use M-Flash.
  services.fwupd.uefiCapsuleSettings.RequireESPFreeSpace = 128;

  # This interactive workstation has sufficient RAM for a volatile /tmp.
  # Builders and memory-constrained hosts choose their own temporary-storage
  # policy instead of inheriting this desktop trade-off.
  boot.tmp.useTmpfs = true;

  users.users.ianmh = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
    description = "Ian Holloway";
    # wheel is required for administration. GPU devices are granted through
    # logind/udev ACLs to the active graphical session; `uinput` is the narrow
    # additional permission Sunshine needs for virtual controller, keyboard,
    # and mouse input. `tss` permits access to the kernel TPM resource manager
    # for deliberate TPM key management, not the raw TPM device. Rootless
    # Docker needs no root-equivalent docker group.
    extraGroups = [
      "wheel"
      "ianmh"
      "tss"
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
  };

  # Determinate Nixd is the Nix daemon on this host and owns garbage
  # collection. Do not run NixOS's legacy nix-gc timer alongside it.
  # This mirrors the automatic collection policy used on the MacBook.
  environment.etc."determinate/config.json".text = builtins.toJSON {
    garbageCollector.strategy = "automatic";
  };

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
