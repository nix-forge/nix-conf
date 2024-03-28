{
  # The flake inputs
  inputs,
  # The type of system to build for
  system,
  # The tree of file paths
  tree,
  # Refer to vars defined in flake
  self,
  # The input of nixpkgs to use for the host.
  nixpkgs ? inputs.nixpkgs,
  # Arguments to be given to nixpkgs instantiation.
  # <https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/impure.nix>
  nixpkgsArgs ? {},
  # Defines the lib (allows for custom lib to be passed in)
  lib ? nixpkgs.lib,
  # State Version of the system
  stateVersion,
  # Overlays to apply to nixpkgs
  overlays ? [],
  # Additional `specialArgs` (overwrites `args` attributes).
  specialArgs ? {},
  # The modules to include in the system
  nixosModules ? [],
  # define the home-manager flake
  homeManager ? inputs.home-manager,
  # Define the users for the system
  # TODO: move user config to a seprate function that will add users inside NixOS config
  systemUsers ? {
    rootInitialPassword = "password";
    mainUser = {
      username = "user";
      name = "User Name";
      homeModules = [];
      extraGroups = ["wheel" "audio" "video"];
      initialPassword = "password";
    };
    otherUsers = [
      {
        username = "guest";
        name = "Guest User";
        homeModules = [];
        initialPassword = "password";
      }
    ];
  },
  ...
}: let
  # Pkgs
  pkgs =
    import nixpkgs {
      inherit overlays system;
    }
    // nixpkgsArgs;

  # Lib for Home Manager
  libHome = lib.extend (self: super: {
    hm = import "${homeManager}/modules/lib" {lib = self;};
  });

  # SpecialArgs
  baseArgs = specialArgs // {inherit nixpkgs inputs tree self;};
  nixosSpecialArgs = baseArgs // {inherit lib;} // {mainUser = systemUsers.mainUser;};
  homeSpecialArgs = baseArgs // {lib = libHome;};

  # Define users to add
  usersToAdd = [systemUsers.mainUser] ++ systemUsers.otherUsers;

  # Users
  usersConfig = lib.mkMerge [
    (lib.mkMerge (lib.lists.forEach usersToAdd (user: lib.cust.mkUser user)))
    (lib.cust.mkUser {
      username = "root";
      name = lib.mkDefault "System Administrator";
      isNormalUser = false;
      initialPassword = systemUsers.rootInitialPassword;
    })
  ];

  # Users for home-manager
  usersHM = lib.lists.forEach usersToAdd (
    user: {
      home-manager.users.${user.username} = {
        imports = user.homeModules;
        home.stateVersion = stateVersion;
      };
    }
  );

  # Define the home-manager modules
  nixosHomeManager =
    [
      # Import the home-manager NixOS Modules
      homeManager.nixosModules.home-manager
      # General NixOS home-manager config
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = homeSpecialArgs;
      }
    ]
    # Add the home manager users
    ++ usersHM;
in
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = nixosSpecialArgs;
    modules =
      [
        {nixpkgs.pkgs = pkgs;} # Set the Pkgs for the system
        {system.stateVersion = stateVersion;} # Set State Version
        {users.users = usersConfig;} # Define the Users for the System
      ]
      ++ nixosModules
      ++ nixosHomeManager;
  }
