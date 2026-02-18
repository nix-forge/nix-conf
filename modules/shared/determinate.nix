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
    let
      inherit (pkgs.stdenv.hostPlatform) isAarch64;
    in
    {
      imports = [ inputs.determinate.darwinModules.default ];

      assertions = [
        {
          assertion = isAarch64;
          message = "Determinate Nix on Darwin only supports aarch64 (Apple Silicon)";
        }
      ];

      determinateNix = {
        enable = true;

        determinateNixd = {
          builder.state = "enabled";
          garbageCollector.strategy = "automatic";
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
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
    in
    {
      assertions = [
        {
          assertion = (!isDarwin) || isAarch64;
          message = "Determinate Nix on Darwin only supports aarch64 (Apple Silicon)";
        }
      ];

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
