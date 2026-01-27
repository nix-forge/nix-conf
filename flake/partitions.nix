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
  
  # Partition definitions
  # Each partition isolates a set of outputs and their dependencies
  partitions = {
    # Development partition - for build tools, formatters, hooks
    dev = {
      module = {
        imports = [ ../dev/flake ];
      };
    };
    
    # NixOS partition - for Linux system configurations
    nixos = {
      module = {
        imports = [ ../nixos/flake ];
      };
    };
    
    # Darwin partition - for macOS system configurations
    darwin = {
      module = {
        imports = [ ../darwin/flake ];
      };
    };
    
    # Home-Manager partition - for user-level configurations
    home = {
      module = {
        imports = [ ../home/flake ];
      };
    };
  };
}
