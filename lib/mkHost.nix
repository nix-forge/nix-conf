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

  # Define Main User for NixOS
  mainUser = systemUsers.mainUser;

  # SpecialArgs
  baseArgs = specialArgs // {inherit nixpkgs inputs tree self;};
  nixosSpecialArgs = baseArgs // {inherit lib mainUser;};
  homeSpecialArgs = baseArgs // {lib = libHome;};

  # Users
  usersConfig = lib.mkMerge [
    (lib.cust.mkUser systemUsers.mainUser) # Main
    (lib.mkMerge (lib.lists.forEach systemUsers.otherUsers (user: lib.cust.mkUser user))) # Others
    (lib.cust.mkUser {
      username = "root";
      name = lib.mkDefault "System Administrator";
      isNormalUser = false;
      initialPassword = systemUsers.rootInitialPassword;
    })
  ];

  # Other Users for home-manager
  otherUsersHM = lib.lists.forEach systemUsers.otherUsers (
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
      # Main User
      {
        home-manager.users.${systemUsers.mainUser.username} = {
          imports = systemUsers.mainUser.homeModules;
          home.stateVersion = stateVersion;
        };
      }
    ]
    # Other Users
    ++ otherUsersHM;
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
