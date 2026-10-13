# Verify the ordinary current package before retiring its installed workaround.
# Actual 26.10 removed the uppercase Themes directory present beside themes in Actual 26.9.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "aarch64-darwin"; };
  upstream = pkgs.actual-server;
  node = pkgs.nodejs_24;
  regression =
    pkgs.runCommand "actual-source-runtime-regression" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp ${./actual-css-result.py} actual-css-result.py
        cp ${./actual-runtime.py} actual-runtime.py
        cp ${./test_actual_proof.py} test_actual_proof.py
        python3 -m unittest discover -s . -p test_actual_proof.py
        touch "$out"
      '';
  sourceLayout =
    pkgs.runCommand "actual-selected-source-layout" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        test -e ${regression}
        python3 ${./actual-css-result.py} ${upstream.src} > "$out"
        cat "$out"
      '';
  rawRuntime = import ../../../tests/nix/actual-runtime.nix {
    inherit pkgs;
    actualPackage = upstream;
  };
in
assert builtins.any (dependency: dependency.drvPath == node.drvPath) upstream.nativeBuildInputs;
assert !(upstream.__noChroot or false);
{
  metadata = {
    nixpkgsRevision = flake.inputs.nixpkgs.rev;
    actualVersion = upstream.version;
    nodeVersion = node.version;
    sourceHash = upstream.src.outputHash;
    rawPackage = upstream.drvPath;
    requiredSandbox = true;
    localNetworking = upstream.__darwinAllowLocalNetworking;
    appliesAnyWorkaround = false;
    usesControlledLayout = false;
  };
  rawPackage = upstream;
  inherit rawRuntime sourceLayout regression;
}
