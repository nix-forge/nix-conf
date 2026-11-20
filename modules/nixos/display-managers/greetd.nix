{
  lib,
  myLib,
  pkgs,
  config,
  ...
}:
let
  checkedShellText = myLib.writers.checkedShellText { inherit pkgs; };
  sessionRoot = "/etc/greetd/sessions";
  defaultSession = config.services.displayManager.defaultSession;
  normalUsers = builtins.attrNames (lib.filterAttrs (_: user: user.isNormalUser) config.users.users);
  prepareCache = (import ../../../flake/runtime-packages.nix { inherit pkgs; }).tuigreetCache;
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

    systemd.services.greetd.preStart = lib.mkIf (defaultSession != null) (checkedShellText {
      name = "prepare-greeter-cache";
      text =
        myLib.templates.renderText
          {
            name = "prepare-greeter-cache.sh";
            text = ''
              # shellcheck shell=bash
              @pkgs_coreutils@/bin/install -d -m 0755 -o greeter -g greeter /var/cache/tuigreet
              # Repair ownership after numeric UID changes without following symlinks.
              # Read and rewrite the user-writable cache only as the greeter account.
              for cache in /var/cache/tuigreet/last*; do
                if [[ -e $cache || -L $cache ]]; then
                  @pkgs_coreutils@/bin/chown --no-dereference greeter:greeter -- "$cache"
                fi
              done
              @pkgs_util_linux@/bin/runuser -u greeter -- @lib_escapeShellArgs_lib_getExe_prepareCache_var_cache_tuigre@
            '';
          }
          {
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
          };
    });
  };
}
