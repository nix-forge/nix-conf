{ lib, ... }: {
  networking.hostName = "nix-guide";
  system.stateVersion = "26.05";
  users.users.learner.isNormalUser = true;

  # Console access belongs to this disposable VM, never to a physical host.
  services.getty.autologinUser = "learner";
  virtualisation = {
    graphics = false;
    memorySize = 1024;
    cores = 2;
  };
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.learner = {
      imports = [ ./home.nix ];
      # Adapting the standalone account must not change the practice VM login.
      home.username = lib.mkForce "learner";
      home.homeDirectory = lib.mkForce "/home/learner";
    };
  };
}
