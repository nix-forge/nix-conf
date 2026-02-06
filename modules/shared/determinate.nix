{
  nixos =
    { inputs, ... }:
    {
      imports = [ inputs.determinate.nixosModules.default ];

      nix.settings = {
        eval-cores = 0;
        lazy-trees = true;
      };
    };

  darwin =
    { inputs, ... }:
    {
      imports = [ inputs.determinate.darwinModules.default ];

      determinateNix = {
        enable = true;

        determinateNixd = {
          builder.state = "enabled";
          garbageCollector.strategy = "automatic";
        };

        customSettings = {
          eval-cores = 0;
          lazy-trees = true;
        };
      };
    };

  homeManager =
    {
      inputs,
      system,
      lib,
      config,
      ...
    }:
    {
      nix.package = inputs.determinate.inputs.nix.packages.${system}.default;

      nix.settings = lib.mkIf (config.nix.package != null) {
        eval-cores = 0;
        lazy-trees = true;
      };

      # Workaround: Disable HM manual to suppress Determinate Nix warning
      # about options.json referencing store paths without proper context.
      # Upstream issue: https://github.com/nix-community/home-manager/issues/7935
      manual.manpages.enable = false;
    };
}
