{ lib, ... }: {
  # This service host has less RAM than a workstation. Actual daemon builders
  # need their own cap in addition to the user queue's read-only-store profile.
  nix.settings = {
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 2;
  };
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "384M";
    MemoryMax = "512M";
    MemorySwapMax = "128M";
    OOMPolicy = "continue";
    CPUWeight = 25;
    IOWeight = 25;
  };
}
