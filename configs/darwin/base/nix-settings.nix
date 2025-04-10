{
  config,
  pkgs,
  lib,
  ...
}:
{
  nix = {
    # Run the Nix daemon on lowest possible priority so that system
    # stays responsive during demanding tasks such as GC and builds.
    # daemonIOSchedClass = "idle";
    # daemonCPUSchedPolicy = "idle";
    # daemonIOSchedPriority = 7;

    # set up garbage collection to run weekly,
    # removing unused packages that are older than 30 days
    # gc = {
    #   automatic = true;
    #   dates = "Sat *-*-* 03:00";
    #   options = "--delete-older-than 30d";
    #   persistent = false; # don't try to catch up on missed GC runs
    # };

    # automatically optimize nix store my removing hard links
    # do it after the gc
    # optimise = {
    #   automatic = true;
    #   dates = [ "04:00" ];
    # };

    # Disable nix channels
    channel.enable = false;

    settings = {
      # automatically optimize symlinks
      auto-optimise-store = true;

      # let the system decide the number of max jobs
      max-jobs = "auto";
      cores = 0;

      allowed-users = [
        "*"
      ];

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
        # "blake3-hashes"
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

  nixpkgs.config = {
    # Allow broken packages to be built. Setting this to false means packages
    # will refuse to evaluate sometimes, but only if they have been marked as
    # broken for a specific reason. At that point we can either try to solve
    # the breakage, or get rid of the package entirely.
    allowBroken = false;
    # allowUnsupportedSystem = true;

    # Default to none, add more as necessary. This is usually where
    # electron packages go when they reach EOL.
    permittedInsecurePackages = [ ];

    # overlays = [
    #   (final: prev: {
    #     # nixos-rebuild provides its own nix package, which is not the same as the one
    #     # we use in the system closure - which causes an extra Nix package to be added
    #     # even if it's not the one we need want.
    #     nixos-rebuild = prev.nixos-rebuild.override { nix = config.nix.package; };
    #   })
    # ];
  };

  # # Enable the Nix garbage collector service on AC power only.
  # systemd.services.nix-gc = {
  #   unitConfig.ConditionACPower = true;
  # };

  # # Set the nix access token for github
  # system.activationScripts.githubTokenAccess = lib.stringAfter [ "agenix" ] ''
  #   echo "access-tokens = github.com=$(cat ${githubAccessToken.path})" > /etc/nix/github-token.conf
  #   chmod 0400 /etc/nix/github-token.conf
  #   chown root:root /etc/nix/github-token.conf
  # '';

  # nix.extraOptions = ''
  #   !include /etc/nix/github-token.conf
  # '';
}
