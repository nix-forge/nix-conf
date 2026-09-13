{
  description = "A neutral Apple silicon nix-darwin example";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { nixpkgs, nix-darwin, ... }:
    let
      system = "aarch64-darwin";
      example = nix-darwin.lib.darwinSystem { modules = [ ./configuration.nix ]; };
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      darwinConfigurations.example = example;
      checks.${system} = {
        inherit (example) system;
        generated-config = import ./tests/generated-config.nix {
          inherit pkgs;
          inherit (example) config;
        };
      };
    };
}
