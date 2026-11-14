{
  lib,
  pkgs,
  config,
  ...
}:
let
  sessionRoot = "/etc/greetd/sessions";
  defaultSession = config.services.displayManager.defaultSession;
  normalUsers = builtins.attrNames (lib.filterAttrs (_: user: user.isNormalUser) config.users.users);
  prepareCache = pkgs.writeShellApplication {
    name = "prepare-tuigreet-cache";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/prepare-tuigreet-cache.sh;
  };
in
{
  options.services.greetd.tuigreet.defaultCommand = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Fallback session command when tuigreet has no remembered selection.";
  };

  config = {
    # Remembered session paths must survive Nix store generation changes.
    environment.etc."greetd/sessions".source = config.services.displayManager.sessionData.desktops;

    services.greetd = {
      enable = true;
      settings.default_session = {
        command = lib.escapeShellArgs (
          [
            (lib.getExe pkgs.tuigreet)
            "--time"
            "--time-format"
            "%I:%M %p | %a • %h | %F"
            "--remember"
            "--remember-user-session"
            "--asterisks"
            "--sessions"
            "${sessionRoot}/share/wayland-sessions"
            "--xsessions"
            "${sessionRoot}/share/xsessions"
          ]
          ++ lib.optionals (config.services.greetd.tuigreet.defaultCommand != null) [
            "--cmd"
            config.services.greetd.tuigreet.defaultCommand
          ]
        );
        user = "greeter";
      };
    };

    systemd.services.greetd.preStart = lib.mkIf (defaultSession != null) (
      (import ../../../lib/templates/text.nix) ./scripts/prepare-greeter-cache.sh {
        pkgs_coreutils = pkgs.coreutils;
        pkgs_util_linux = pkgs.util-linux;
        lib_escapeShellArgs_lib_getExe_prepareCache_var_cache_tuigre = lib.escapeShellArgs (
          [
            (lib.getExe prepareCache)
            "/var/cache/tuigreet"
            sessionRoot
            "${defaultSession}.desktop"
          ]
          ++ normalUsers
        );
      }
    );
  };
}
