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
      }
    ];
  };
in
assert pkgs.lib.all (assertion: assertion.assertion) home.config.assertions;
pkgs.runCommand "public-guide-recipes"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.fzf
      pkgs.fd
    ];
    gitConfig = home.config.xdg.configFile."git/config".source;
    searchCommand = home.config.programs.fzf.defaultCommand;
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$gitConfig"
    git init practice
    git -C practice st > "$TMPDIR/git-status"
    test -s "$TMPDIR/git-status"

    mkdir -p search/{.git,.direnv,node_modules,src}
    touch search/.git/internal search/.direnv/internal search/node_modules/internal
    touch search/src/guide.nix search/.visible-hidden
    cd search
    eval "$searchCommand" > "$TMPDIR/search-results"
    grep -Fx 'src/guide.nix' "$TMPDIR/search-results"
    grep -Fx '.visible-hidden' "$TMPDIR/search-results"
    test "$(wc -l < "$TMPDIR/search-results")" -eq 2
    test "$(fzf --filter guide < "$TMPDIR/search-results")" = src/guide.nix
    touch "$out"
  ''
