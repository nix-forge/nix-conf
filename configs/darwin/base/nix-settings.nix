{ config, ... }:
{
  nix = {
    # Run the Nix daemon on lowest possible priority so that system
    # stays responsive during demanding tasks such as GC and builds.
    # daemonIOSchedClass = "idle";
    # daemonCPUSchedPolicy = "idle";
    # daemonIOSchedPriority = 7;

    # set up garbage collection to run weekly,
    # removing unused packages that are older than 30 days
    gc = {
      automatic = true;
      #   dates = "Sat *-*-* 03:00";
      #   options = "--delete-older-than 30d";
      #   persistent = false; # don't try to catch up on missed GC runs
    };

    # automatically optimize nix store my removing hard links
    # do it after the gc
    optimise = {
      automatic = true;
      # dates = [ "04:00" ];
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
        "@admin"
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
        # "blake3-hashes"
        "ca-derivations"
        "verified-fetches"
      ];

      # don't warn that my git tree is dirty it is known through git
      warn-dirty = false;

      # maximum number of parallel TCP connections used to fetch imports and binary caches, 0 means no limit
      http-connections = 35;

      # Whether to accept nix configuration from a flake without displaying a Y/N prompt.
      accept-flake-config = false;

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      # use binary cache, this is not gentoo
      # external builders can also pick up those substituters
      builders-use-substitutes = true;
    };
  };

  nix.extraOptions = ''
    !include ${config.age.secrets.nix-access-tokens.path}
  '';
}
