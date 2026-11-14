{ pkgs }:
let
  inherit (pkgs) lib;
  integrationFor =
    isLinux:
    import ../../homes/shared/local/nix-seal.nix {
      inherit lib;
      pkgs.stdenv.hostPlatform = { inherit isLinux; };
      config.nixSeal = {
        runtimeDirectory = "%t/sealed fixture";
        templates.refined-github-token-import.path = "%t/sealed fixture/current/templates/import fixture";
      };
    };
  rules = (integrationFor true).systemd.user.tmpfiles.rules.content;
  disabled = (integrationFor false).systemd.user.tmpfiles.rules;
  ruleFile = pkgs.writeText "refined-github-import.conf" (lib.concatStringsSep "\n" rules + "\n");
in
assert !disabled.condition;
pkgs.runCommand "refined-github-import" {
  # A real namespace root avoids Nix's unmapped-owner / → /build transition.
  # Drop to an ordinary user before exercising systemd's unchanged path checks.
  requiredSystemFeatures = [ "uid-range" ];
  SETPRIV = lib.getExe' pkgs.util-linux "setpriv";
  PYTHON = lib.getExe pkgs.python3;
  CHECK = ../secrets/check_refined_github_import.py;
  RULES = ruleFile;
  TMPFILES = lib.getExe' pkgs.systemd "systemd-tmpfiles";
} (builtins.readFile ../secrets/run-refined-github-import.sh)
