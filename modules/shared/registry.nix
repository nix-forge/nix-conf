let
  # The registry is a CLI convenience layer, not a dependency mechanism.
  # Keep flake inputs explicit in flake.nix so each project records its own
  # dependencies in flake.lock.
  mkRegistry = { inputs, self, ... }: {
    # Keep this list deliberately short. Every store-path alias retains its
    # input source in the active system closure.
    nixpkgs = {
      flake = inputs.nixpkgs;
      exact = true;
    };
    self = {
      flake = self;
      exact = true;
    };
  };

  # Nix resolves registries in this order: global, system, user, command
  # line. A managed system registry is enough here. Disabling the mutable,
  # network-fetched global registry avoids a request during indirect flake
  # resolution and prevents undeclared aliases from changing underneath us.
  nixSettings = {
    flake-registry = "";
  };
in
{
  nixos = args: {
    nix = {
      registry = mkRegistry args;
      settings = nixSettings;
    };
  };

  darwin =
    args@{ lib, config, ... }:
    let
      registry = mkRegistry args;
      usingDeterminateNix = lib.hasAttr "determinateNix" config && config.determinateNix.enable;
    in
    lib.mkMerge [
      (lib.mkIf (!usingDeterminateNix) {
        nix = {
          inherit registry;
          settings = nixSettings;
        };
      })
      # The Determinate nix-darwin module renders this registry at
      # /etc/nix/registry.json and points Determinate Nix at it. Do not put
      # flake-registry in customSettings as that would fight its generated
      # setting.
      (lib.mkIf usingDeterminateNix { determinateNix.registry = registry; })
    ];

  homeManager =
    args@{ lib, config, ... }:
    {
      # Standalone Home Manager owns a client registry. OS-managed Home
      # Manager configurations leave nix.package null, so the system registry
      # remains the single source of truth.
      nix = lib.mkIf (config.nix.package != null) {
        registry = mkRegistry args;
        settings = nixSettings;
      };
    };
}
