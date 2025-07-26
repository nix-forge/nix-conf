{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Push the user's nix.conf into /etc/nix/nix.custom.conf,
  # leaving determinate-nixd to manage /etc/nix/nix.conf
  environment.etc."nix/nix.conf".target = "nix/nix.custom.conf";

  nix = {
    # Run the Nix daemon on lowest possible priority so that system
    # stays responsive during demanding tasks such as GC and builds.
    daemonIOSchedClass = "idle";
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedPriority = 7;

    # set up garbage collection to run weekly,
    # removing unused packages that are older than 30 days
    gc = {
      automatic = true;
      dates = "Sat *-*-* 03:00";
      options = "--delete-older-than 30d";
      persistent = false; # don't try to catch up on missed GC runs
    };

    # automatically optimize nix store my removing hard links
    # do it after the gc
    optimise = {
      automatic = true;
      dates = [ "04:00" ];
    };

    # Disable nix channels
    channel.enable = false;

    settings = {
      # Set auto-optimise-store to false to prevent corruption
      auto-optimise-store = false;

      # let the system decide the number of max jobs
      max-jobs = "auto";
      cores = 0;

      allowed-users = [ "*" ];

      # only allow sudo users to manage the nix store
      trusted-users = [
        "root"
        "@wheel"
        "@sudo"
        "nix-builder"
      ];

      # build inside sandboxed environments
      sandbox = true;
      sandbox-fallback = false;

      # continue building derivations if one fails
      keep-going = true;

      # If we haven't received data for >= 20s, retry the download
      stalled-download-timeout = 20;

      # bail early on missing cache hits
      connect-timeout = 5;

      # show more log lines for failed builds
      log-lines = 30;

      # enable extra experimental features
      extra-experimental-features = [
        "nix-command"
        "flakes"
        "auto-allocate-uids"
        "blake3-hashes"
        "ca-derivations"
        "cgroups"
        "verified-fetches"
      ];

      # don't warn that my git tree is dirty it is known through git
      warn-dirty = false;

      # maximum number of parallel TCP connections used to fetch imports and binary caches, 0 means no limit
      http-connections = 35;

      # Whether to accept nix configuration from a flake without displaying a Y/N prompt.
      accept-flake-config = false;

      # Whether to execute builds inside cgroups. cgroups are
      # "a Linux kernel feature that limits, accounts for, and
      # isolates the resource usage (CPU, memory, disk I/O, etc.)
      # of a collection of processes."
      # See:
      # <https://en.wikipedia.org/wiki/Cgroups>
      use-cgroups = pkgs.stdenv.isLinux;

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      # use binary cache, this is not gentoo
      # external builders can also pick up those substituters
      builders-use-substitutes = true;

      # Extra Experimental Features
      auto-allocate-uids = true;
    };
  };

  # environment.etc."nix/nix.custom.conf".text = lib.mkForce ''
  #   auto-optimise-store = true

  #   auto-allocate-uids = true

  #   max-jobs = auto
  #   cores = 0
  #   require-sigs = true

  #   keep-going = true

  #   allowed-users = *
  #   trusted-users = root @wheel @sudo

  #   sandbox = true
  #   sandbox-fallback = false

  #   # https://manual.determinate.systems/development/experimental-features
  #   extra-experimental-features = nix-command flakes auto-allocate-uids blake3-hashes ca-derivations cgroups verified-fetches

  #   warn-dirty = false

  #   # Increase the number of http connections to 35
  #   http-connections = 35

  #   # Automatically accept the flake config
  #   accept-flake-config = true

  #   # Allow nix to execute builds inside cgroups
  #   use-cgroups = ${if pkgs.stdenv.isLinux then "true" else "false"}

  #   # Keep derivations and outputs
  #   keep-derivations = true
  #   keep-outputs = true

  #   stalled-download-timeout = 20
  #   connect-timeout = 5
  #   log-lines = 30

  #   # Use the binary cache
  #   builders-use-substitutes = true
  #   always-allow-substitutes = true

  #   # include the access token for github
  #   !include /etc/nix/github-token.conf

  #   # Extra
  #   bash-prompt-prefix = (nix:$name)\040
  #   netrc-file = /nix/var/determinate/netrc
  #   require-sigs = true

  #   substituters = https://cache.nixos.org/
  #   trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=

  #   extra-trusted-substituters = https://cache.flakehub.com
  #   extra-trusted-public-keys = cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM= cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio= cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU= cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU= cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8= cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ= cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o= cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y=

  #   extra-nix-path = nixpkgs=flake:https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/*.tar.gz
  # '';

  nixpkgs.config = {
    # Allow broken packages to be built. Setting this to false means packages
    # will refuse to evaluate sometimes, but only if they have been marked as
    # broken for a specific reason. At that point we can either try to solve
    # the breakage, or get rid of the package entirely.
    allowBroken = false;
    allowUnsupportedSystem = true;

    # Default to none, add more as necessary. This is usually where
    # electron packages go when they reach EOL.
    permittedInsecurePackages = [ ];

    overlays = [
      (final: prev: {
        # nixos-rebuild provides its own nix package, which is not the same as the one
        # we use in the system closure - which causes an extra Nix package to be added
        # even if it's not the one we need want.
        nixos-rebuild = prev.nixos-rebuild.override { nix = config.nix.package; };
      })
    ];
  };

  # Enable the Nix garbage collector service on AC power only.
  systemd.services.nix-gc = {
    unitConfig.ConditionACPower = true;
  };

  nix.extraOptions = ''
    !include /etc/nix/github-token.conf
  '';
}
