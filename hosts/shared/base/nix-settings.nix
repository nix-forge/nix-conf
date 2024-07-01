{
  inputs,
  config,
  pkgs,
  ...
}:
{
  nix = {
    # set the nix super package
    package = inputs.nix-super.packages.${pkgs.system}.default;

    # make builds run with low priority so my system stays responsive
    # this is especially helpful if you have auto-upgrade on
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;

    # set up garbage collection to run weekly,
    # removing unused packages that are older than 30 days
    gc = {
      automatic = true;
      dates = "Sat *-*-* 03:00";
      options = "--delete-older-than 30d";
    };

    # automatically optimize nix store my removing hard links
    # do it after the gc
    optimise = {
      automatic = true;
      dates = [ "04:00" ];
    };

    settings = {
      # Free up to 10GiB whenever there is less than 5GB left.
      # this setting is in bytes, so we multiply with 1024 thrice
      min-free = "${toString (5 * 1024 * 1024 * 1024)}";
      max-free = "${toString (10 * 1024 * 1024 * 1024)}";

      # automatically optimise symlinks
      auto-optimise-store = true;

      # let the system decide the number of max jobs
      max-jobs = "auto";

      # allow sudo users to mark the following values as trusted
      allowed-users = [
        "root"
        "@wheel"
        "nix-builder"
      ];

      # only allow sudo users to manage the nix store
      trusted-users = [
        "root"
        "@wheel"
        "nix-builder"
      ];

      # build inside sandboxed environments
      sandbox = true;
      sandbox-fallback = false;

      # continue building derivations if one fails
      keep-going = true;

      # bail early on missing cache hits
      connect-timeout = 5;

      # show more log lines for failed builds
      log-lines = 30;

      # enable extra experimental features
      extra-experimental-features = [
        "flakes" # flakes
        "nix-command" # experimental nix commands
      ];

      # don't warn me that my git tree is dirty, I know
      warn-dirty = false;

      # maximum number of parallel TCP connections used to fetch imports and binary caches, 0 means no limit
      http-connections = 50;

      # whether to accept nix configuration from a flake without prompting
      accept-flake-config = false;

      # for direnv GC roots
      keep-derivations = true;
      keep-outputs = true;

      # use binary cache, this is not gentoo
      # external builders can also pick up those substituters
      builders-use-substitutes = true;
    };
  };

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
}
