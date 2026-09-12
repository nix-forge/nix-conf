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
      pkgs.python3
      pkgs.fzf
      pkgs.fd
    ];
    gitConfig = home.config.xdg.configFile."git/config".source;
    promptConfig = home.config.home.file."${home.config.xdg.configHome}/starship.toml".source;
    bashConfig = home.config.home.file.".bashrc".source;
    searchCommand = home.config.programs.fzf.defaultCommand;
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    test "$(git config --file "$gitConfig" init.defaultBranch)" = main
    test "$(git config --file "$gitConfig" alias.st)" = 'status --short --branch'
    test "$(git config --file "$gitConfig" merge.conflictStyle)" = zdiff3
    test "$(git config --file "$gitConfig" pull.rebase)" = true
    test -z "$(git config --file "$gitConfig" user.email || true)"
    export GIT_CONFIG_GLOBAL="$gitConfig"
    git init practice
    git -C practice st | grep -F 'No commits yet on main'

    mkdir -p search/{.git,.direnv,node_modules,src}
    touch search/.git/internal search/.direnv/internal search/node_modules/internal
    touch search/src/guide.nix search/.visible-hidden
    cd search
    eval "$searchCommand" > "$TMPDIR/search-results"
    grep -Fx 'src/guide.nix' "$TMPDIR/search-results"
    grep -Fx '.visible-hidden' "$TMPDIR/search-results"
    test "$(wc -l < "$TMPDIR/search-results")" -eq 2
    test "$(fzf --filter guide < "$TMPDIR/search-results")" = src/guide.nix
    grep -F 'starship init bash' "$bashConfig"

    python3 - "$promptConfig" <<'PY'
    import sys
    import tomllib
    with open(sys.argv[1], "rb") as source:
        config = tomllib.load(source)
    assert config["command_timeout"] == 250
    assert config["scan_timeout"] == 30
    assert config["format"] == "$username$hostname$directory$character"
    assert "$git_branch" in config["right_format"]
    assert config["hostname"]["ssh_only"]
    PY
    touch "$out"
  ''
