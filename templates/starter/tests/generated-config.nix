{ pkgs, home }:
pkgs.runCommand "starter-generated-config"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.python3
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/empty-home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    config=${home.config.xdg.configFile."git/config".source}
    test "$(git config --file "$config" init.defaultBranch)" = main
    test "$(git config --file "$config" pull.ff)" = only
    test "$(git config --file "$config" alias.st)" = 'status --short --branch'
    test -z "$(git config --file "$config" user.email || true)"
    grep -F "gs='git status --short --branch'" ${home.config.home.file.".bashrc".source}
    python3 - ${home.config.home.file."${home.config.xdg.configHome}/starship.toml".source} <<'PY'
    import sys
    import tomllib
    with open(sys.argv[1], "rb") as source:
        prompt = tomllib.load(source)
    assert prompt["character"]["success_symbol"] == "[>](bold green)"
    assert prompt["directory"]["style"] == "bold blue"
    PY
    touch "$out"
  ''
