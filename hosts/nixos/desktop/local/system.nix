{
  config,
  lib,
  pkgs,
  ...
}:
{
  nix.settings = {
    # This 30 GiB interactive desktop exhausted RAM during concurrent builds.
    # The shared auto/0 settings allow 16 builds, each using all 16 CPUs.
    # Two large builders also exceed the daemon's reclaim threshold.
    # Keep one derivation at a time, with eight compiler jobs on 16 threads.
    # The aggregate CPU and memory limits retain interactive headroom.
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 8;
    # A representative package evaluation took comparable time with four and
    # sixteen evaluator threads. Bound evaluation separately from builders so
    # it does not request all logical CPUs during interactive work.
    eval-cores = lib.mkForce 8;
  };

  # Bound daemon builders separately from user-side Nix evaluations.
  systemd.services.nix-daemon.serviceConfig = {
    # Eight parallel Node/V8 workers stalled at the former 7/8 GiB limits.
    # The reviewed working set and admission reserve share one policy.
    MemoryHigh = config.workstation.workloads.daemon.highMiB * 1024 * 1024;
    MemoryMax = config.workstation.workloads.daemon.memoryMiB * 1024 * 1024;
    MemorySwapMax = config.workstation.workloads.daemon.swapMiB * 1024 * 1024;
    CPUWeight = 50;
    # Cargo job limits do not constrain test-created worker pools. On this
    # 16-thread desktop, cap the whole daemon at 70% of logical CPU capacity
    # while retaining lower scheduling priority when interactive work runs.
    # systemd quotas are percentages of one CPU, so 16 * 70% = 1120%.
    CPUQuota = "1120%";
    # A failed builder must not cause systemd to stop all daemon connections.
    OOMPolicy = "continue";
  };

  # User applications are exported through overlapping Nix profiles and XDG
  # service directories. The reference daemon handles their search precedence
  # without treating repeated exports of the same service as errors. Keep the
  # system broker, and use the dbus package's own socket-activated user unit.
  systemd.user.services.dbus-broker = {
    enable = false;
    aliases = lib.mkForce [ ];
  };
  systemd.user.services.dbus.restartTriggers = [ config.environment.etc."dbus-1".source ];

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
  # GVfs starts wsdd on demand when GNOME Files browses Windows network shares.
  # Supply its upstream executable so the discovery backend can start.
  environment.systemPackages = with pkgs; [
    seahorse
    wsdd
  ];

  # Greetd supplies the login password to GNOME Keyring. Hyprlock retains
  # the same hook for later session unlocks; the boot PIN is independent.
  # The native UI variant retains the upstream PAM termination deadlock fix
  # and adds a guarded submit control without replacing authentication.
  programs.hyprlock = {
    enable = true;
    package = pkgs.hyprlock-personal;
  };
  # NixOS ships Hypridle's user unit, but that unit starts without the UWSM
  # XDG environment and therefore cannot discover Home Manager's config at
  # boot. Give the host-owned unit each user's persistent config explicitly.
  systemd.user.services.hypridle.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${lib.getExe config.services.hypridle.package} -c %h/.config/hypr/hypridle.conf"
  ];
  security.pam.services = {
    hyprlock = {
      enableGnomeKeyring = true;
      # This desktop uses password authentication and has no fingerprint reader.
      fprintAuth = false;
      allowNullPassword = false;
      failDelay = {
        enable = true;
        delay = 3000000;
      };
    };

    # NixOS enables the Keyring hooks for `login`, which greetd's interactive
    # path includes. Also enable the password-change hook: otherwise a later
    # `passwd` change can leave the Login keyring encrypted with an obsolete
    # password and cause the separate prompt Helium reported.
    passwd.enableGnomeKeyring = true;
  };

  assertions = [
    {
      assertion = !(config.services.greetd.settings ? initial_session);
      message = "The desktop requires authenticated greetd login.";
    }
  ];

  # This password-based greetd stack includes PAM's `login` service. Reject
  # null-password accounts despite the permissive shadow-program default,
  # retain a short failure delay against rapid local guessing, and show the
  # most recent successful login for basic user-visible auditing. `su` is
  # intentionally limited to wheel administrators; remote SSH passwords are
  # already disabled in the SSH policy. Do not enable pam_gnupg: this account
  # has no managed private-key/keygrip preset configuration to unlock.
  security.pam.services = {
    login = {
      # First login supplies the password that opens GNOME Keyring.
      fprintAuth = false;
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

  # /tmp reached roughly 15 GiB on this 30 GiB workstation. tmpfs keeps its
  # contents in memory (and can swap them), so large development caches and
  # abandoned scratch trees competed directly with the desktop and build
  # budgets. Keep /tmp on the root filesystem and restore its conventional
  # ephemeral lifetime at boot; the root filesystem has ample free space.
  boot.tmp = {
    useTmpfs = false;
    cleanOnBoot = true;
  };

  users.users.ianmh = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
    description = "IanHollow";
    # wheel is required for administration. GPU devices are granted through
    # logind/udev ACLs to the active graphical session. `tss` permits access
    # to the kernel TPM resource manager for deliberate TPM key management, not the raw TPM device. Rootless
    # Docker needs no root-equivalent docker group.
    extraGroups = [
      "wheel"
      "ianmh"
      "tss"
    ];
    openssh.authorizedKeys.keys = [
      "${lib.removeSuffix "\n" (builtins.readFile ../../../../homes/macbook-pro-m4/local/nix-seal/identity.pub)} deployment-client"
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
    "restrict ${lib.removeSuffix "\n" (builtins.readFile ../../../../homes/macbook-pro-m4/local/nix-seal/identity.pub)} deployment-client"
  ];

  # `nh` is the local interface for building and activating this host.  Keep
  # its flake path unset: the checkout may live on a different filesystem on
  # the desktop than it does on the MacBook.  From a checkout, use
  # `nh os switch . -H desktop`.  deploy-rs remains the remote deployment path,
  # because its activation protocol supplies the connectivity rollback guard.
  programs.nh.enable = true;

  # Determinate Nix owns automatic garbage collection on this host, so do not
  # enable nh's clean timer as a competing collector.

  system.activationSafety.enable = true;

}
