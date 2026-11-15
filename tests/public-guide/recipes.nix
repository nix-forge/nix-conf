{
  pkgs,
  home-manager,
  modules ? [
    ../../modules/home/dev/git.nix
    ../../modules/home/shells/fzf.nix
    ../../modules/home/shells/integration.nix
    ../../modules/home/shells/starship.nix
  ],
}:
let
  home = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = modules ++ [
      {
        home = {
          username = "guide-check";
          homeDirectory =
            if pkgs.stdenv.hostPlatform.isDarwin then "/Users/guide-check" else "/home/guide-check";
          stateVersion = "26.05";
        };
        programs.bash.enable = true;
        # This recipe checks aliases, not the production credential helper or
        # Git LFS. Keep their large package closures out of the smoke test.
        programs.git = {
          package = pkgs.lib.mkForce pkgs.gitMinimal;
          lfs.enable = pkgs.lib.mkForce false;
          settings.credential.helper = pkgs.lib.mkForce "";
        };
      }
    ];
  };
in
assert pkgs.lib.all (assertion: assertion.assertion) home.config.assertions;
pkgs.runCommand "public-guide-recipes" {
  nativeBuildInputs = [
    pkgs.gitMinimal
    pkgs.fzf
    pkgs.fd
  ];
  gitConfig = home.config.xdg.configFile."git/config".source;
  searchCommand = home.config.programs.fzf.defaultCommand;
} (builtins.readFile ./scripts/public-guide-recipes.sh)
