{
  description = "Consumer of the documented source-file imports";
  inputs = {
    nix-conf-source = {
      url = "github:nix-forge/nix-conf";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nix-conf-source,
      nixpkgs,
      home-manager,
      ...
    }:
    {
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system: {
        recipes = import ./recipes.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit home-manager;
          modules = [
            (nix-conf-source + "/modules/home/dev/git.nix")
            (nix-conf-source + "/modules/home/shells/fzf.nix")
            (nix-conf-source + "/modules/home/shells/integration.nix")
            (nix-conf-source + "/modules/home/shells/starship.nix")
          ];
        };
      });
    };
}
