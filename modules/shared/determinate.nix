let
  settings = {
    eval-cores = 0;
    lazy-trees = true;
  };
in
{
  nixos =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.determinate.nixosModules.default ];
      options.nix.determinateNixdSettings = lib.mkOption {
        inherit ((pkgs.formats.json { })) type;
        default = { };
        description = "Host additions to Determinate Nixd configuration; one collector must own reclamation.";
      };
      config = {
        determinate.enable = true;
        nix = { inherit settings; };
        environment.etc."determinate/config.json".text = builtins.toJSON (
          lib.recursiveUpdate { garbageCollector.strategy = "automatic"; } config.nix.determinateNixdSettings
        );
      };
    };

  darwin =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
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

      # Determinate Nixd owns the Nix daemon and its socket on Darwin.  The
      # legacy multi-user installer plist is unmanaged once `nix.enable` is
      # disabled, so nix-darwin intentionally preserves it.  Remove that
      # redundant daemon after its activation step has completed.
      system.activationScripts.postActivation.text = lib.mkAfter (
        builtins.readFile ./determinate-assets/remove-legacy-nix-daemon.sh
      );

    };

  homeManager =
    {
      inputs,
      lib,
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

      imports = [ inputs.determinate.homeManagerModules.default ];

      # Determinate owns Darwin's Nix configuration and leaves HM's package
      # null. Do not ask Home Manager to generate a second nix.conf without
      # a corresponding package; the host's customSettings remain authoritative.
      nix.enable = lib.mkIf isDarwin false;

      # Workaround: Disable HM manual to suppress Determinate Nix warning
      # about options.json referencing store paths without proper context.
      # Upstream issue: https://github.com/nix-community/home-manager/issues/7935
      manual.manpages.enable = false;
    };
}
