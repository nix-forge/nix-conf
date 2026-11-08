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
pkgs.runCommand "refined-github-import" { } ''
  ${lib.getExe pkgs.python3} ${../secrets/check_refined_github_import.py} \
    --rules ${ruleFile} --tmpfiles ${lib.getExe' pkgs.systemd "systemd-tmpfiles"}
  touch "$out"
''
