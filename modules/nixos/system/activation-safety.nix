{
  config,
  lib,
  pkgs,
  ...
}:
let
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
        updateDiff = (import ../../../lib/templates/text.nix) ./activation-safety-assets/show-diff.sh {
          pkgs_nvd = pkgs.nvd;
        };
      })
      (lib.mkIf cfg.checkHostname {
        expectedHostname =
          (import ../../../lib/templates/text.nix) ./activation-safety-assets/check-hostname.sh
            { expectedHostname = lib.escapeShellArg config.networking.hostName; };
      })
      (lib.mkIf cfg.checkDeploymentIdentity {
        deploymentIdentity =
          (import ../../../lib/templates/text.nix) ./activation-safety-assets/check-deployment-identity.sh
            { deploymentIdentity = lib.escapeShellArg cfg.deploymentIdentity; };
      })
    ];
  };
}
