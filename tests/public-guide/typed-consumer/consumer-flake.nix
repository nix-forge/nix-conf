{
  description = "Consumer of the advertised typed Home Manager module exports";
  inputs = {
    nix-conf.url = "git+https://github.com/nix-forge/nix-conf?submodules=1";
    nixpkgs.follows = "nix-conf/nixpkgs";
    home-manager.follows = "nix-conf/home-manager";
  };
  outputs =
    {
      nix-conf,
      nixpkgs,
      home-manager,
      ...
    }:
    {
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system: {
        recipes = import ./recipes.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit home-manager;
          modules = with nix-conf.modules.homeManager; [
            dev-git
            shells-fzf
            shells-integration
            shells-starship
          ];
        };
      });
    };
}
