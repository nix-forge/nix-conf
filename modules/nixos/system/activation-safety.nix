{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  renderCheck =
    name: src: replacements:
    checkedShellText {
      inherit name;
      text = myLib.templates.renderText src replacements;
    };
  cfg = config.system.activationSafety;
in
{
  key = "nix-conf/activation-safety/nixos";
  options.system.activationSafety = {
    enable = lib.mkEnableOption "generation review and host checks before activation";
    showDiff = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show the nvd diff before switching generations.";
    };
    checkHostname = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Reject activating another host's configuration. EXPECTED_HOSTNAME explicitly permits an intentional hostname migration.";
    };
    deploymentIdentity = lib.mkOption {
      type = lib.types.strMatching "([A-Za-z0-9][A-Za-z0-9._-]{0,127})?";
      default = "";
      description = "Stable nonsecret identity selected by an operational deployment overlay. Later activations must preserve it.";
    };
    checkDeploymentIdentity = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Refuse a candidate that omits or changes the running deployment identity. Disable explicitly only for an intentional deployment migration.";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.etc = lib.optionalAttrs (cfg.deploymentIdentity != "") {
      "nixos/deployment-id".text = cfg.deploymentIdentity;
    };
    assertions = [
      {
        assertion = !cfg.checkHostname || config.networking.hostName != "";
        message = "system.activationSafety.checkHostname requires a nonempty networking.hostName.";
      }
    ];
    system.preSwitchChecks = lib.mkMerge [
      (lib.mkIf cfg.showDiff {
        updateDiff = renderCheck "show-activation-diff" {
          name = "show-diff.sh";
          text = ''
            # shellcheck shell=bash
            incoming="''${1-}"
            if [[ -e /run/current-system && -n $incoming ]]; then
              echo "--- diff to current system"
              PATH="$incoming/sw/bin:$PATH" @pkgs_nvd@/bin/nvd diff /run/current-system "$incoming"
              echo "---"
            fi
          '';
        } { pkgs_nvd = pkgs.nvd; };
      })
      (lib.mkIf cfg.checkHostname {
        expectedHostname = renderCheck "check-activation-hostname" {
          name = "check-hostname.sh";
          text = ''
            # shellcheck shell=bash
            actual="$(</proc/sys/kernel/hostname)"
            expected=@expectedHostname@
            if [[ -e /run/booted-system && $actual != "$expected" && ''${EXPECTED_HOSTNAME:-} != "$expected" ]]; then
              echo "refusing to activate '$expected' on host '$actual'" >&2
              echo "set EXPECTED_HOSTNAME='$expected' only for an intentional hostname migration" >&2
              exit 1
            fi
          '';
        } { expectedHostname = lib.escapeShellArg config.networking.hostName; };
      })
      (lib.mkIf cfg.checkDeploymentIdentity {
        deploymentIdentity = renderCheck "check-activation-deployment-identity" {
          name = "check-deployment-identity.sh";
          text = ''
            # shellcheck shell=bash
            identity_file=/run/current-system/etc/nixos/deployment-id
            expected=@deploymentIdentity@
            if [[ -e $identity_file || -L $identity_file ]]; then
              actual="$(<"$identity_file")"
              if [[ ! $actual =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ || $actual != "$expected" ]]; then
                echo 'refusing to omit or change the running deployment identity' >&2
                echo 'use the operational deployment flake; an intentional migration must explicitly disable the identity check' >&2
                exit 1
              fi
            fi
          '';
        } { deploymentIdentity = lib.escapeShellArg cfg.deploymentIdentity; };
      })
    ];
  };
}
