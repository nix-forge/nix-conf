# Review the dependency actually selected by the locked Determinate Nix CLI.
# This isolated proof exercises upstream after retiring the local repair.
let
  root = toString ../../..;
  flake = (builtins.getAttr "getFlake" builtins) ("git+file://" + root + "?submodules=1");
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  sentry = import ../../../tests/nix/sentry/package.nix {
    inputs = flake.inputs;
    system = "x86_64-linux";
  };
in
{
  metadata = {
    determinateRevision = flake.inputs.determinate.rev;
    nixRevision = flake.inputs.determinate.inputs.nix.rev;
    sentryVersion = sentry.version;
    sourceHash = sentry.src.outputHash;
  };
  upstream =
    (import ../../../tests/nix/sentry/crashpad-lock.nix {
      inherit (pkgs) python3;
      # This selected Crashpad source includes the upstream contention fix.
      expectNoisyContention = false;
    })
      sentry;
}
