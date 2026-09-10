{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.git.emailPrivacy;
  guard = pkgs.writers.writePython3Bin "git-email-privacy" {
    # Match Ruff's formatting of long lines, slices, and binary operators.
    flakeIgnore = [
      "E203"
      "E501"
      "W503"
    ];
  } ./scripts/git-privacy-hook.py;
  command =
    event:
    lib.escapeShellArgs [
      (lib.getExe guard)
      "--git"
      (lib.getExe' config.programs.git.package "git")
      "--gh"
      (lib.getExe pkgs.gh)
      "--policy-file"
      cfg.policyFile
      event
    ];
in
{
  options.programs.git.emailPrivacy = {
    enable = lib.mkEnableOption "private email checks on commits and outgoing Git history";
    policyFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute runtime path to an owner-readable JSON policy. Never put its private values in Nix expressions.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast config.programs.git.package.version "2.55";
        message = "Git email privacy requires Git 2.55 or newer for configured hooks.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.policyFile;
        message = "Git email privacy needs an absolute runtime policy path.";
      }
    ];
    # Git runs configured hooks alongside ordinary repository hooks. No global
    # hooksPath, hook forwarding, or hook-installer changes are necessary.
    programs.git.settings.hook = {
      email-privacy-commit = {
        event = "commit-msg";
        command = command "commit-msg";
      };
      email-privacy-push = {
        event = "pre-push";
        command = command "pre-push";
      };
    };
  };
}
