{ ... }:
{
  # set up garbage collection to run weekly,
  # removing unused packages after seven days
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
  };

  nix.settings = {
    # divide cores between jobs and reserve some for the system
    cores =
      let
        # number of logical cores to reserve for other processes
        reserveCores = 2;
      in
      (16 - reserveCores);
    # max concurrent jobs
    max-jobs = "auto";
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
  };
}
