let
  providers = {
    nix-community = {
      url = "https://nix-community.cachix.org";
      key = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
    };
    hyprland = {
      url = "https://hyprland.cachix.org";
      key = "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=";
    };
    cuda = {
      url = "https://cache.nixos-cuda.org";
      key = "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=";
    };
    noctalia = {
      url = "https://noctalia.cachix.org";
      key = "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=";
    };
  };

  # These are host/client-wide trust decisions, not derivation properties.
  # Keep the reviewed providers explicit; never import an input's trust keys.
  policy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      homes = builtins.attrValues (config.home-manager.users or { });
      # Profiles that select this module can request a cache explicitly. Other
      # profiles still contribute through their enabled program options.
      homeUsesCache =
        name: fallback: home:
        home.nix.caches.${name}.enable or (fallback home);
    in
    {
      options.nix.caches = lib.mapAttrs (name: provider: {
        enable = lib.mkOption {
          type = lib.types.bool;
          description = ''
            Use the signed ${name} binary cache at ${provider.url}.
            This trusts its signing key for any matching store path, not just
            packages from that project. Override the feature-derived default
            here when using individual package overrides or a different provider.
          '';
        };
      }) providers;

      config.nix.caches = {
        nix-community.enable = lib.mkDefault true;
        cuda.enable = lib.mkDefault (
          pkgs.stdenv.hostPlatform.isLinux
          && ((pkgs.config.cudaSupport or false) || lib.any (homeUsesCache "cuda" (_: false)) homes)
        );
        hyprland.enable = lib.mkDefault (
          pkgs.stdenv.hostPlatform.isLinux
          && (
            (config.programs.hyprland.enable or false)
            || (config.programs.hyprlock.enable or false)
            || (config.wayland.windowManager.hyprland.enable or false)
            || lib.any (homeUsesCache "hyprland" (
              home:
              (home.wayland.windowManager.hyprland.enable or false) || (home.programs.hyprlock.enable or false)
            )) homes
          )
        );
        noctalia.enable = lib.mkDefault (
          (config.programs.noctalia.enable or false)
          || lib.any (homeUsesCache "noctalia" (home: home.programs.noctalia.enable or false)) homes
        );
      };
    };

  settingsFor =
    config:
    let
      selected = builtins.filter (name: config.nix.caches.${name}.enable) (builtins.attrNames providers);
    in
    {
      builders-use-substitutes = true;
      substituters = map (name: providers.${name}.url) selected;
      trusted-public-keys = map (name: providers.${name}.key) selected;
      # Configured substituters already authorize client selection. Reserve
      # trusted-substituters for approved caches that are not used by default.
    };
in
{
  nixos = { config, ... }: {
    imports = [ policy ];
    # NixOS adds cache.nixos.org and its key. List merging preserves them.
    nix.settings = settingsFor config;
  };

  darwin =
    {
      lib,
      config,
      options,
      ...
    }:
    let
      usingDeterminateNix = config.determinateNix.enable or false;
      settings = settingsFor config;
    in
    {
      imports = [ policy ];
      config = lib.mkMerge [
        (lib.mkIf (!usingDeterminateNix) { nix = { inherit settings; }; })
        # Determinate owns the base FlakeHub endpoints and signing keys.
        # Extend its lists so authenticated services and the builder keep working.
        (lib.optionalAttrs (options ? determinateNix) (
          lib.mkIf usingDeterminateNix {
            determinateNix.customSettings = {
              inherit (settings) builders-use-substitutes;
              extra-substituters = settings.substituters;
              extra-trusted-public-keys = settings.trusted-public-keys;
            };
          }
        ))
      ];
    };

  homeManager =
    {
      lib,
      config,
      pkgs,
      ...
    }@args:
    let
      hostManagesCaches = args ? osConfig && args.osConfig.nix ? caches;
    in
    {
      imports = [ policy ];
      nix = {
        package = lib.mkDefault pkgs.nix;
        # Integrated homes contribute policy to the host above. Keep daemon
        # settings in one place, including when the host opts out of a cache.
        # Standalone client settings remain subject to the daemon's trust.
        settings = lib.mkIf (!hostManagesCaches && config.nix.package != null) (
          let
            settings = settingsFor config;
          in
          {
            inherit (settings) builders-use-substitutes;
            extra-substituters = settings.substituters;
            extra-trusted-public-keys = settings.trusted-public-keys;
          }
        );
      };
    };
}
