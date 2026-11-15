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
      # HTTP fixtures bind loopback only; Darwin's build sandbox requires this
      # explicit permission even when the tests use no external network.
      __darwinAllowLocalNetworking = true;
      sandboxProfile = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
        builtins.readFile ../flake/dev/fsevents.sb
      );
    }
  )
  (
    (import ../lib/templates/text.nix) ./scripts/run-python-tests.sh {
      inherit source;
      inherit prepare;
      pkgs_lib_escapeShellArg_selection = pkgs.lib.escapeShellArg selection;
      pkgs_lib_escapeShellArgs_testPaths = pkgs.lib.escapeShellArgs testPaths;
    }
  )
