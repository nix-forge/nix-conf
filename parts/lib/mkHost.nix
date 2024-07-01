{
  # The flake inputs
  inputs,
  # The type of system to build for
  system,
  # Refer to vars defined in flake
  self,
  # Defines the lib (allows for custom lib to be passed in)
  lib,
  # Define the host name
  hostName,
  # State Version of the system
  stateVersion,
  # The input of nixpkgs to use for the host.
  nixpkgs ? inputs.nixpkgs,
  # Arguments to be given to nixpkgs instantiation.
  # <https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/impure.nix>
  nixpkgsArgs ? { },
  # Overlays to apply to nixpkgs
  overlays ? [ ],
  # Additional `specialArgs` (overwrites `args` attributes).
  specialArgs ? { },
  # The modules to include in the system
  nixosModules ? [ ],
  # define the home-manager flake
  homeManager ? inputs.home-manager,
  # withSystem
  withSystem,
  ...
}:
let
  # Pkgs
  pkgs = import nixpkgs (
    {
      inherit system;
      overlays = overlays ++ [ (import "${homeManager}/overlay.nix") ];
    }
    // nixpkgsArgs
  );

  # Lib for Home Manager
  libHome = lib.extend (self: super: { hm = import "${homeManager}/modules/lib" { lib = self; }; });

  # SpecialArgs
  baseArgs = specialArgs // {
    inherit nixpkgs inputs self;
  };
  nixosSpecialArgs = baseArgs // {
    inherit lib;
  };
  homeSpecialArgs = baseArgs // {
    lib = lib // libHome;
  };

  # Define the home-manager modules
  nixosHomeManager = [
    # Import the home-manager NixOS Modules
    homeManager.nixosModules.home-manager
    # General NixOS home-manager config
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = homeSpecialArgs;
      home-manager.backupFileExtension = "backup";
    }
  ];
in

nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = nixosSpecialArgs;
  modules = [
    { nixpkgs.pkgs = pkgs; } # Set the Pkgs for the system
    { system.stateVersion = stateVersion; } # Set State Version
    { networking.hostName = hostName; }
  ] ++ nixosModules ++ nixosHomeManager;
}
