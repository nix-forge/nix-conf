{ inputs, lib, ... }:
let
  cacheModule = import ../../modules/shared/cache.nix;
  official = "https://cache.nixos.org/";
  community = "https://nix-community.cachix.org";
  cuda = "https://cache.nixos-cuda.org";
  hyprland = "https://hyprland.cachix.org";
  noctalia = "https://noctalia.cachix.org";
  same = a: b: lib.sort builtins.lessThan a == lib.sort builtins.lessThan b;
  mkNixos =
    modules:
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ cacheModule.nixos ] ++ modules;
    }).config;
  base = mkNixos [ ];
  withCuda = mkNixos [ { nixpkgs.config.cudaSupport = true; } ];
  withHyprland = mkNixos [ { programs.hyprland.enable = true; } ];
  withHyprlock = mkNixos [ { programs.hyprlock.enable = true; } ];
  optedOut = mkNixos [
    {
      nixpkgs.config.cudaSupport = true;
      programs.hyprland.enable = true;
      nix.caches.cuda.enable = false;
      nix.caches.hyprland.enable = false;
      nix.caches.nix-community.enable = false;
    }
  ];
  # Package-local CUDA overrides do not change pkgs.config.cudaSupport.
  optedIn = mkNixos [ { nix.caches.cuda.enable = true; } ];
  integratedHome = {
    home-manager.users.cache-check = {
      imports = [ cacheModule.homeManager ];
      home.stateVersion = "25.05";
      nix.caches.cuda.enable = true;
    };
  };
  mkIntegrated =
    modules:
    mkNixos (
      [
        inputs.home-manager.nixosModules.home-manager
        integratedHome
      ]
      ++ modules
    );
  integratedCuda = mkIntegrated [ ];
  integratedOptOut = mkIntegrated [ { nix.caches.cuda.enable = false; } ];
  externalHost =
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.home-manager.nixosModules.home-manager
        integratedHome
      ];
    }).config;
  allProviders = mkNixos [
    {
      nix.caches = {
        nix-community.enable = true;
        cuda.enable = true;
        hyprland.enable = true;
        noctalia.enable = true;
      };
    }
  ];
  plainDarwin =
    (inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [ cacheModule.darwin ];
    }).config;
  mkHome =
    extraModules:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        cacheModule.homeManager
        {
          home.username = "cache-check";
          home.homeDirectory = "/home/cache-check";
          home.stateVersion = "25.05";
        }
      ]
      ++ extraModules;
    }).config;
  standalone = mkHome [ { programs.hyprlock.enable = true; } ];
  unmanagedClient = mkHome [ { nix.package = null; } ];
  desktop = inputs.self.nixosConfigurations.desktop.config;
  withoutNoctalia =
    (inputs.self.nixosConfigurations.desktop.extendModules {
      modules = [ { home-manager.users.ianmh.desktop.noctalia.enable = lib.mkForce false; } ];
    }).config;
  macbook = inputs.self.darwinConfigurations.macbook-pro-m4.config;
  bootstrap = (import ../../flake.nix).nixConfig;
in
{
  perSystem = { pkgs, ... }: {
    checks.cache-policy =
      assert same base.nix.settings.substituters [
        official
        community
      ];
      assert same withCuda.nix.settings.substituters [
        official
        community
        cuda
      ];
      assert same withHyprland.nix.settings.substituters [
        official
        community
        hyprland
      ];
      assert same withHyprlock.nix.settings.substituters [
        official
        community
        hyprland
      ];
      assert same optedOut.nix.settings.substituters [ official ];
      assert same optedIn.nix.settings.substituters [
        official
        community
        cuda
      ];
      assert lib.elem cuda integratedCuda.nix.settings.substituters;
      assert !(integratedCuda.home-manager.users.cache-check.nix.settings ? extra-substituters);
      assert !(lib.elem cuda integratedOptOut.nix.settings.substituters);
      assert lib.elem cuda externalHost.home-manager.users.cache-check.nix.settings.extra-substituters;
      assert same plainDarwin.nix.settings.substituters [
        official
        community
      ];
      assert same standalone.nix.settings.extra-substituters [
        community
        hyprland
      ];
      assert !(unmanagedClient.nix.settings ? extra-substituters);
      assert !(standalone.nix.settings ? trusted-substituters);
      assert base.nix.settings.trusted-substituters == [ ];
      assert base.nix.settings.require-sigs;
      assert
        optedOut.nix.settings.trusted-public-keys
        == [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
      assert same desktop.nix.settings.substituters [
        official
        community
        cuda
        hyprland
        noctalia
      ];
      assert !(lib.elem noctalia withoutNoctalia.nix.settings.substituters);
      assert same macbook.determinateNix.customSettings.extra-substituters [ community ];
      assert !(macbook.determinateNix.customSettings ? substituters);
      assert !(macbook.determinateNix.customSettings ? trusted-public-keys);
      assert !(macbook.determinateNix.customSettings ? extra-trusted-substituters);
      # Compare the complete provider catalog independently of host selections.
      # Disabling a desktop feature must not break bootstrap consistency checks.
      assert same bootstrap.extra-substituters (
        lib.remove official allProviders.nix.settings.substituters
      );
      assert same bootstrap.extra-trusted-public-keys (
        lib.remove "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" allProviders.nix.settings.trusted-public-keys
      );
      pkgs.runCommand "cache-policy" { } "touch $out";
  };
}
