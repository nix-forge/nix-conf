{ self, ... }:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
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
    checks =
      (map (system: requirement "starter" "home" "build" system) systems)
      ++ [
        (requirement "public-demo" "graphical-session" "vm" "x86_64-linux")
        (requirement "darwin-example" "system" "build" "aarch64-darwin")
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

  perSystem = { pkgs, ... }: {
    packages.workstation-evidence = pkgs.writeShellApplication {
      name = "workstation-evidence";
      runtimeInputs = [
        pkgs.python3
        pkgs.git
      ];
      text = ''
        exec python3 ${../scripts/workstation_evidence.py} "$@"
      '';
    };
    packages.validation-manifest = pkgs.writeText "validation-manifest.json" (
      builtins.toJSON self.validationManifest
    );
  };
}
