{ self, ... }:
let
  requirement = target: check: phase: system: {
    inherit
      target
      check
      phase
      system
      ;
    required = true;
  };
in
{
  flake.validationManifest = {
    schema = 1;
    checks = [
      (requirement "desktop" "full-system" "build" "x86_64-linux")
      (requirement "desktop" "full-system" "dry-activation" "x86_64-linux")
      (requirement "desktop" "full-system" "activation" "x86_64-linux")
      (requirement "macbook-pro-m4" "full-system" "build" "aarch64-darwin")
      (requirement "macbook-pro-m4" "full-system" "activation" "aarch64-darwin")
    ]
    ++ (map (check: requirement "desktop" check "runtime" "x86_64-linux") [
      "login"
      "locking"
      "audio"
      "portals"
      "screen-sharing"
      "suspend-resume"
      "display"
      "rollback"
    ])
    ++ [ (requirement "desktop" "application-restore" "recovery" "x86_64-linux") ];
  };

  perSystem =
    { myLib, pkgs, ... }:
    let
      runtime = import ../../../../flake/runtime-packages.nix { inherit pkgs; };
    in
    {
      packages.workstation-evidence = myLib.writers.writeShellApplication { inherit pkgs; } {
        name = "workstation-evidence";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.coreutils
        ];
        text = ''
          exec ${pkgs.lib.getExe runtime.workstationEvidence} --build-policy ${../build-policy.json} "$@"
        '';
      };
      packages.validation-manifest = pkgs.writeText "validation-manifest.json" (
        builtins.toJSON self.validationManifest
      );
    };
}
