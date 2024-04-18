{
  host,
  lib,
  self,
  ...
}:
{
  imports = [
    # Import NixOS modules that have options used acrossed multiple files in shared
    self.nixosModules.users
  ];

  # set up garbage collection to run weekly,
  # removing unused packages after seven days
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
  };

  # use a lower priority for builds
  # so that the system is still usable with the following (extreme) settings
  nix.daemonCPUSchedPolicy = "batch";
  nix.daemonIOSchedClass = "idle";

  # enable dconf
  programs.dconf.enable = true;

  nix.settings = rec {
    # allow the flake settings
    # accept-flake-config = true;
    # set a minimum free space so that garbage collection
    # runs more aggressively during a build
    min-free = lib.bird.bytes.GiB 30;
    # keep the derivations from which active store paths are built
    keep-derivations = true;
    # keep the outputs (source files for example) of
    # derivations which are associated with active store paths
    keep-outputs = true;
    # divide cores between jobs and reserve some for the system
    cores =
      let
        # number of logical cores to reserve for other processes
        reserveCores = 2;
      in
      (host.logicalProcessors - reserveCores) / max-jobs;
    # max concurrent jobs
    max-jobs = 4;
    # allow sudo users to mark the following values as trusted
    trusted-users = [
      "root"
      "@wheel"
    ];
    # only allow sudo users to manage the nix store
    allowed-users = [ "@wheel" ];
    # enable new nix command and flakes
    extra-experimental-features = [
      "flakes"
      "nix-command"
    ];

    # TODO: Make this Flake nixConfig
    # continue building derivations if one fails
    keep-going = true;
    # show more log lines for failed builds
    log-lines = 20;
  };
}
