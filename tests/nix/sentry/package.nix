{ inputs, system }:
let
  inherit (inputs.nixpkgs) lib;
  packages = inputs.determinate.inputs.nix.packages.${system};
in
(lib.findSingle (package: (package.pname or "") == "sentry-native")
  (throw "Determinate CLI no longer selects Sentry; review the regression check")
  (throw "Determinate CLI selects multiple Sentry dependencies; review the regression check")
  packages.nix-cli.buildInputs
).out
