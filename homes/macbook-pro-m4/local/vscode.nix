{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [ "rust-lang.rust-analyzer" ];

    userSettings = {
      "[rust]" = {
        "editor.defaultFormatter" = "rust-lang.rust-analyzer";
        "editor.formatOnSave" = true;
      };
      "rust-analyzer.server.path" = lib.getExe pkgs.rust-analyzer;
      "rust-analyzer.check.command" = "clippy";
      "rust-analyzer.check.allTargets" = true;
      "rust-analyzer.check.extraArgs" = [
        "--"
        "-D"
        "warnings"
      ];
      "rust-analyzer.cargo.allTargets" = true;
    };
  };

  programs.vscode.profiles.default.userSettings = {
    "remote.SSH.serverInstallPath" = {
      "perlmutter.nersc.gov" = "/pscratch/sd/i/imh39";
      "perlmutter-agent" = "/pscratch/sd/i/imh39";
    };
    "remote.SSH.maxReconnectionAttempts" = 2;
    "remote.SSH.useFlock" = false;
  };
}
