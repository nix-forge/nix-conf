let
  settings = {
    eval-cores = 0;
    lazy-trees = true;
  };
in
{
  nixos =
    { inputs, ... }:
    {
      imports = [ inputs.determinate.nixosModules.default ];

      nix = { inherit settings; };
    };

  darwin =
    { inputs, pkgs, ... }:
    {
      imports = [ inputs.determinate.darwinModules.default ];

      determinateNix = {
        enable = true;

        determinateNixd.garbageCollector.strategy = "automatic";

        # Use the local NixOS VM-based Linux builder (free, no FlakeHub auth needed).
        nixosVmBasedLinuxBuilder = {
          enable = true;
          package = pkgs.darwin.linux-builder-x86_64;
        };

        customSettings = settings;
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
      nix = {
        package = inputs.determinate.inputs.nix.packages.${system}.default;
        settings = lib.mkIf (config.nix.package != null) settings;
      };

      # Workaround: Disable HM manual to suppress Determinate Nix warning
      # about options.json referencing store paths without proper context.
      # Upstream issue: https://github.com/nix-community/home-manager/issues/7935
      manual.manpages.enable = false;
    };
}
