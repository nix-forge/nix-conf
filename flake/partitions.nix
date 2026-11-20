{ inputs, ... }: {
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    apps = "dev";
    checks = "dev";
    libTests = "dev";
    devShells = "dev";
    formatter = "dev";
  };

  partitions.dev = {
    extraInputsFlake = ./dev;
    module.imports = [ ./dev ];
  };
}
