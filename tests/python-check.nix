# Run fixture-based Python behavior tests with the same policy as local pytest.
{ pkgs }:
{
  name,
  files,
  testPaths ? [ "tests" ],
  nativeBuildInputs ? [ ],
  environment ? { },
  prepare ? "",
  selection ? "not nix_integration and not nix_daemon",
}:
let
  source = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions ([ ../pyproject.toml ] ++ files);
  };
  python = import ../flake/dev/test-python.nix { inherit pkgs; };
in
pkgs.runCommand name
  (
    environment
    // {
      nativeBuildInputs = [ python ] ++ nativeBuildInputs;
      PYTEST_DISABLE_PLUGIN_AUTOLOAD = "1";
    }
  )
  ''
    cp -R ${source}/. .
    chmod -R u+w .
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    mkdir -p "$HOME"
    ${prepare}
    mkdir -p "$out"
    python3 -m pytest -m ${pkgs.lib.escapeShellArg selection} \
      --junitxml="$out/junit.xml" ${pkgs.lib.escapeShellArgs testPaths}
  ''
