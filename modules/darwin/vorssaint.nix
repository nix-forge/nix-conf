{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vorssaint.clamshellMode;
  validUser = user: builtins.match "[A-Za-z0-9._-]+" user != null;
in
{
  options.services.vorssaint.clamshellMode = {
    enable = lib.mkEnableOption "Vorssaint closed-lid mode";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        Local account allowed to toggle the closed-lid setting. The value must
        exactly match the macOS account name used to run Vorssaint.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != null && validUser cfg.user;
        message = "services.vorssaint.clamshellMode.user must be a valid local macOS account name.";
      }
    ];

    # This is precisely the rule Vorssaint normally asks an administrator to
    # install interactively. Keeping it in /etc/sudoers.d makes the privilege
    # declarative and removes it automatically when the module is disabled.
    # It grants no shell access and permits only the two state changes used by
    # the feature.
    environment.etc."sudoers.d/vorssaint-clamshell".source = pkgs.replaceVarsWith {
      name = "vorssaint-clamshell-sudoers";
      src = ./vorssaint-sudoers.in;
      replacements.user = cfg.user;
    };
  };
}
