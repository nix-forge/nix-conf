# Review the dependency actually selected by the locked Determinate Nix CLI.
# This isolated proof does not apply or advance installed configuration guards.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  packages = flake.inputs.determinate.inputs.nix.packages.x86_64-linux;
  sentry =
    (lib.findSingle (package: (package.pname or "") == "sentry-native")
      (throw "Determinate CLI no longer selects Sentry; review the probe")
      (throw "Determinate CLI selects multiple Sentry dependencies; review the probe")
      packages.nix-cli.buildInputs
    ).out;
  repaired = (import ../sentry-crashpad-lock.nix { inherit pkgs; }).apply sentry;
in
{
  metadata = {
    determinateRevision = flake.inputs.determinate.rev;
    nixRevision = flake.inputs.determinate.inputs.nix.rev;
    sentryVersion = sentry.version;
    sourceHash = sentry.src.outputHash;
  };
  upstream =
    (import ./crashpad-lock.nix {
      inherit (pkgs) python3;
      expectNoisyContention = true;
    })
      sentry;
  inherit (repaired.tests) crashpad-lock;
  lifecycle =
    pkgs.runCommand "current-sentry-patch-lifecycle"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.patch
          pkgs.python3
        ];
      }
      ''
        python3 ${./crashpad-lock-lifecycle.py} \
          ${sentry.src} \
          ${../patches/apply-crashpad-lock.sh} \
          ${../patches/sentry-crashpad-lock.patch}
        touch "$out"
      '';
}
