{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    # checks = "dev";
    # devShells = "dev";
    formatter = "dev";
  };
  partitions.dev = {
    extraInputsFlake = ../dev;
    module.imports = [ ../dev/flake ];
  };
}
