{ inputs, ... }:
let
  home-manager = extraSpecialArgs: {
    # Enable verbose output for debugging
    verbose = true;

    # Use system-level nixpkgs for consistency
    useGlobalPkgs = true;

    # Enable user packages through users.users.<name>.packages
    useUserPackages = true;

    # Backup existing files instead of failing
    backupFileExtension = "hm.old";

    # Pass custom args to Home Manager modules
    inherit extraSpecialArgs;
  };
in
{
  nixos =
    extraSpecialArgs:
    { ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = home-manager extraSpecialArgs;
    };

  darwin =
    extraSpecialArgs:
    { ... }:
    {
      imports = [ inputs.home-manager.darwinModules.home-manager ];

      home-manager = home-manager extraSpecialArgs;
    };
}
