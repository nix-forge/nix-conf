{
  description = "Ian's NixOS Configuration";

  # The inputs of the flake
  inputs = {
    # The Nixpkg flakes
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs.follows = "nixpkgs-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Systems
    systems.url = "github:nix-systems/default";

    # Bird Nix Lib
    bird-nix-lib.url = "github:spikespaz/bird-nix-lib";

    # NUR
    nur.url = "github:nix-community/NUR";

    # VS Code
    vscode-insider = {
      url = "github:iosmanthus/code-insiders-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Hyprland Flake
    hyprland-xdph.url = "github:hyprwm/xdg-desktop-portal-hyprland";
    hyprland-protocols.url = "github:hyprwm/xdg-desktop-portal-hyprland";
    hyprlang.url = "github:hyprwm/hyprlang";
    hyprland.url = "github:hyprwm/Hyprland/v0.40.0";

    # Hyprland Nix Configuration
    hyprnix = {
      url = "github:hyprland-community/hyprnix";
      inputs = {
        hyprland.follows = "hyprland";
        hyprland-xdph.follows = "hyprland-xdph";
        hyprland-protocols.follows = "hyprland-protocols";
        hyprlang.follows = "hyprlang";
      };
    };

    # Firefox BetterFox
    firefox-betterfox = {
      url = "github:yokoffing/Betterfox";
      flake = false;
    };

    # Firefox Lepton UI
    firefox-lepton-ui = {
      url = "github:black7375/Firefox-UI-Fix";
      flake = false;
    };

    # Spicetify
    spicetify-nix = {
      url = "github:the-argus/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix gaming
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Wayland Packages
    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";

    # Nix Language Server
    nixd.url = "github:nix-community/nixd";

    # BirdOS
    birdos.url = "github:spikespaz/dotfiles";

    # Nix Direnv
    nix-direnv = {
      url = "github:nix-community/nix-direnv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    # instances of cachix for package derivations
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
    ];
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      systems,
      ...
    }:
    let
      inherit (self) lib tree; # Allow referencing defined lib and tree
      eachSystem = lib.genAttrs (import systems); # Define to allow packages for multiple systems
    in
    {
      # Overlay default lib with new lib
      # New lib docs -> https://github.com/spikespaz/bird-nix-lib
      # Default lib docs -> https://teu5us.github.io/nix-lib.html
      lib = nixpkgs.lib // {
        bird = lib.extend inputs.bird-nix-lib.lib.overlay; # Bird Nix Lib
        cust = import ./lib { lib = nixpkgs.lib; }; # My Custom Lib
      };

      # Define tree to refer to any file path in the config starting from the root
      tree =
        let
          configRoot = ./.;
          excludes = [ "flake.nix" ]; # flake.nix is excluded to prevent infinite recursion
        in
        lib.bird.importDirRecursive configRoot excludes;

      # Nix formatter for this flake
      formatter = eachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt-rfc-style
      );

      # System Modules
      nixosModules = lib.bird.importDir' ./_nixosModules null;

      # Home Modules
      homeModules = lib.bird.importDir' ./_homeModules null;

      # System Configuration
      # Look at each host in the hosts directory and allow them to inherit the vars if needed
      nixosConfigurations =
        let
          hostsDir = ./hosts;
          excludes = [ "shared" ]; # "shared" directory will store configs shared between hosts
          vars = {
            inherit
              self
              lib
              tree
              inputs
              nixpkgs
              ;
          };
        in
        lib.mapAttrs (host: config: lib.bird.applyAutoArgs config vars) (
          lib.bird.importDir' hostsDir excludes
        );

      # Define standalone Home Manager configurations
      homeConfigurations = { };
    };
}
