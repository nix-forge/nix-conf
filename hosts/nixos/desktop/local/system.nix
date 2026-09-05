{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # Noctalia's pinned `cachix` branch is built by its upstream CI. Nix accepts
  # only store paths signed by this explicit public key; unsigned or altered
  # substitutes still fail verification.
  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

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
  # SSH_AUTH_SOCK. oo7 also depends on a PAM-supplied password, so it would not
  # improve the headless-login flow and would require a separate keyring-data
  # migration.
  security.desktopKeyring.enable = true;
  programs.ssh.startAgent = false;
  environment.systemPackages = [ pkgs.seahorse ];

  # The Sunshine session boots directly into Hyprland in order to provide a
  # capture target, then immediately locks with Hyprlock. Feed the
  # one password entered at that lock screen to GNOME Keyring as well. That
  # unlocks the encrypted Login keyring before Helium starts using Secret
  # Service, without leaving an unlocked desktop at the physical console.
  # Use Hyprlock's current upstream flake. It includes the PAM termination
  # deadlock fix that prevents a stale lock process from leaving Hyprland on
  # its crashed-lockscreen fallback.
  programs.hyprlock = {
    enable = true;
    package = inputs.hyprlock.packages.${pkgs.stdenv.hostPlatform.system}.hyprlock;
  };
  # NixOS ships Hypridle's user unit, but that unit starts without the UWSM
  # XDG environment and therefore cannot discover Home Manager's config at
  # boot. Give the host-owned unit the persistent user config explicitly.
  systemd.user.services.hypridle.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${lib.getExe config.services.hypridle.package} -c /home/ianmh/.config/hypr/hypridle.conf"
  ];
  security.pam.services = {
    hyprlock.enableGnomeKeyring = true;

    # NixOS enables the Keyring hooks for `login`, which greetd's interactive
    # path includes. Also enable the password-change hook: otherwise a later
    # `passwd` change can leave the Login keyring encrypted with an obsolete
    # password and cause the separate prompt Helium reported.
    passwd.enableGnomeKeyring = true;
  };

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
        PATH="$incoming/sw/bin:$PATH" ${pkgs.nvd}/bin/nvd diff /run/current-system "$incoming"
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

  # The rootless Docker module installs a global user unit. Limit it to the
  # actual desktop user so the greeter never gets a Docker daemon.
  systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce "ianmh";
}
