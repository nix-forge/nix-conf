{ nixpkgs, lib, ... }:
let
  inherit nixpkgs;
  inherit (lib.lists) singleton concatLists;
  inherit (lib.modules) mkDefault;
  inherit (lib.attrsets) recursiveUpdate;

  # shorthand alias to `lib.nixosSystem`
  # `lib.nixosSystem` is a shallow wrapper around `lib.evalModules` that passes
  # a few specialArgs and modules to bootstrap a working NixOS system. This is
  # done implicitly in the wrapper and normally we would like to avoid using it
  # however using `evalModules` to evaluate a system closure breaks e.g. the
  # `documentation.nixos.enable` option which evaluates the module tree internally
  # in which case `baseModules` will be missing
  mkSystem = lib.nixosSystem;

  # global module path for nixos modules
  # while using nixosSystem, this will be set as a specialArgs internally
  # modulesPath = "${nixpkgs}/nixos/modules";

  # mkNixosSystem is a convenient wrapper around lib.nixosSystem (which itself is a wrapper around lib.evalModules)
  # that allows us to abstract host creation and configuration with necessary modules and specialArgs pre-defined
  # or properly overridden compared to their nixpkgs default. This allows us to swiftly bootstrap a new system
  # when (not if) a new system is added to `hosts/default.nix` with minimum lines of code rewritten each time.
  # Ultimately this defines specialArgs we need and lazily merges any args and modules the host may choose
  # to pass to the builder.
  mkHost =
    {
      withSystem,
      system,
      folderName,
      inputs,
      lib,
      determinate,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        homeManager = inputs.home-manager;
        overlays = args.overlays or [ ];

        # Lib for Home Manager
        libHome = lib.extend (self: super: { hm = import "${homeManager}/modules/lib" { lib = self; }; });

        # SpecialArgs
        baseArgs = {
          inherit inputs' self';
          inherit inputs;
          self = args.self or { };
          tree = args.tree or { };
        } // (args.specialArgs or { });

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
          (
            { config, ... }:
            let
              nixosConfig = config;
            in
            {
              home-manager = {
                # tell home-manager to be as verbose as possible
                verbose = true;

                # use the system configuration’s pkgs argument
                # this ensures parity between nixos' pkgs and hm's pkgs
                useGlobalPkgs = true;

                # enable the usage user packages through
                # the users.users.<name>.packages option
                useUserPackages = true;

                # move existing files to the .hm.old suffix rather than failing
                # with a very long error message about it
                backupFileExtension = "hm.old";

                # extra specialArgs passed to Home Manager
                # for reference, the config argument in nixos can be accessed
                # in home-manager through osConfig without us passing it
                extraSpecialArgs = homeSpecialArgs // {
                  inherit nixosConfig;
                };

                # configuration options for all user configs
                sharedModules = [
                  # Import AgeNix for managing secrets and install agenix package
                  inputs.agenix.homeManagerModules.default
                  {
                    home.packages = [ inputs.agenix.packages.${system}.agenix ];
                  }
                ];
              };
            }
          )
        ];

        # Default Custom Options Modules
        defaultCustomOptions = [
          {
            # Add a option which can be used to find all normal users if setup properly
            options.users = {
              normalUsers = lib.mkOption {
                # type set
                type = lib.types.listOf lib.types.attrs;
                default = [ ];
              };
            };
          }
        ];
      in
      mkSystem {
        # specialArgs
        specialArgs = nixosSpecialArgs;

        # Modules
        modules = concatLists [
          (singleton {
            networking.hostName = args.hostname or args.hostName or folderName;
            nixpkgs = {
              overlays = overlays ++ [ (import "${homeManager}/overlay.nix") ];
              hostPlatform = system;
              flake.source = nixpkgs.outPath;
            } // (args.nixpkgsArgs or { });
          })

          # if host needs additional modules, append them
          # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
          (lib.cust.withTreeModules (args.modules or [ ]))

          # Determinate
          [ determinate.nixosModules.default ]

          # Home Manager modules
          nixosHomeManager

          # Add AgeNix nixosModules
          [
            inputs.agenix.nixosModules.default
            {
              environment.systemPackages = [ inputs.agenix.packages.${system}.agenix ];
            }
          ]

          # Add custom options that are required for all hosts
          defaultCustomOptions
        ];
      }
    );

  mkDarwin =
    {
      withSystem,
      system,
      inputs,
      folderName,
      lib,
      ...
    }@args:
    withSystem system (
      { inputs', self', ... }:
      let
        nixDarwin = inputs.nix-darwin;
        homeManager = inputs.home-manager;

        # Lib for Home Manager
        libHome = lib.extend (self: super: { hm = import "${homeManager}/modules/lib" { lib = self; }; });

        # SpecialArgs
        baseArgs = {
          inherit inputs' self';
          inherit inputs;
          self = args.self or { };
          tree = args.tree or { };
        } // (args.specialArgs or { });

        darwinSpecialArgs = baseArgs // {
          inherit lib;
        };

        homeSpecialArgs = baseArgs // {
          lib = lib // libHome;
        };

        # Define the home-manager modules
        darwinHomeManager = [
          # Import the home-manager darwinModules Modules
          homeManager.darwinModules.home-manager
          # General darwin home-manager config
          (
            { config, ... }:
            let
              darwinConfig = config;
            in
            {
              home-manager = {
                # tell home-manager to be as verbose as possible
                verbose = true;

                # use the system configuration’s pkgs argument
                # this ensures parity between nixos' pkgs and hm's pkgs
                useGlobalPkgs = true;

                # enable the usage user packages through
                # the users.users.<name>.packages option
                useUserPackages = true;

                # move existing files to the .hm.old suffix rather than failing
                # with a very long error message about it
                backupFileExtension = "hm.old";

                # extra specialArgs passed to Home Manager
                # for reference, the config argument in nixos can be accessed
                # in home-manager through osConfig without us passing it
                extraSpecialArgs = homeSpecialArgs // {
                  inherit darwinConfig;
                };

                # configuration options for all user configs
                sharedModules = [ inputs.mac-app-util.homeManagerModules.default ];
              };
            }
          )
        ];
      in
      nixDarwin.lib.darwinSystem {
        specialArgs = darwinSpecialArgs;

        modules = concatLists [
          # Base Config
          (singleton {
            networking.hostName = args.hostname or args.hostName or folderName;
            nixpkgs = {
              hostPlatform = system;
              flake.source = nixpkgs.outPath;
            } // (args.nixpkgsArgs or { });
          })

          # if host needs additional modules, append them
          # NOTE: withTreeModules shouldn't cause issues if tree modules aren't used
          (lib.cust.withTreeModules (args.modules or [ ]))

          # Mac App Util
          [ inputs.mac-app-util.darwinModules.default ]

          # Home Manager modules
          darwinHomeManager
        ];
      }
    );
in
{
  inherit
    mkSystem
    mkHost
    mkDarwin
    ;
}
