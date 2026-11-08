{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vscode.rust;
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  key = "nix-conf/vscode/rust/homeManager";
  imports = [ ../default.nix ];
  options.programs.vscode.rust = {
    analyzerPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rust-analyzer;
      description = "Rust analyzer used by the editor. Cargo and toolchains remain owned by each project.";
    };
    allTargets = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Analyze and check all Cargo targets.";
    };
    denyWarnings = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Treat Clippy warnings as errors in editor checks.";
    };
  };
  config.programs.vscode.profiles.default = {
    extensions = extensions.forVscode [ "rust-lang.rust-analyzer" ];
    userSettings = {
      "[rust]" = {
        "editor.defaultFormatter" = lib.mkDefault "rust-lang.rust-analyzer";
        "editor.formatOnSave" = lib.mkDefault true;
      };
      "rust-analyzer.server.path" = lib.mkDefault (lib.getExe cfg.analyzerPackage);
      "rust-analyzer.check.command" = lib.mkDefault "clippy";
      "rust-analyzer.check.allTargets" = lib.mkDefault cfg.allTargets;
      "rust-analyzer.check.extraArgs" = lib.mkDefault (
        lib.optionals cfg.denyWarnings [
          "--"
          "-D"
          "warnings"
        ]
      );
      "rust-analyzer.cargo.allTargets" = lib.mkDefault cfg.allTargets;
    };
  };
}
