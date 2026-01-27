{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    # Development tools
    checks = "dev";
    devShells = "dev";
    formatter = "dev";
    
    # Platform-specific configurations
    nixosConfigurations = "nixos";
    darwinConfigurations = "darwin";
    homeConfigurations = "home";
  };
  
  partitions = {
    # Development partition - for build tools, formatters, hooks
    dev = {
      extraInputs = {
        inherit (inputs) nixpkgs systems flake-parts;
      };
      extraInputsFlake = ../dev;
      module.imports = [ ../dev/flake ];
    };
    
    # NixOS partition - for Linux system configurations
    nixos = {
      extraInputs = {
        inherit (inputs) nixpkgs;
      };
      extraInputsFlake = ../nixos;
      module.imports = [ ../nixos/flake ];
    };
    
    # Darwin partition - for macOS system configurations
    darwin = {
      extraInputs = {
        inherit (inputs) nixpkgs;
      };
      extraInputsFlake = ../darwin;
      module.imports = [ ../darwin/flake ];
    };
    
    # Home-Manager partition - for user-level configurations
    home = {
      extraInputs = {
        inherit (inputs) nixpkgs;
      };
      extraInputsFlake = ../home;
      module.imports = [ ../home/flake ];
    };
  };
}
