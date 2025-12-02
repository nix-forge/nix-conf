{
  uid ? null,
}:
{
  lib,
  pkgs,
  config,
  ...
}@args:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
in
{
  xdg = {
    enable = true;

    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
    cacheHome = "${config.home.homeDirectory}/.cache";

    userDirs = lib.mkIf isLinux {
      enable = true;
      createDirectories = true;
    };
  };

  home.preferXdgDirectories = config.xdg.enable;

  launchd.agents = lib.mkIf isDarwin {
    xdg-runtime =
      let
        setXdgRuntime = pkgs.writeShellScript "hm-set-xdg-runtime" ''
          set -euo pipefail
          uid="$(/usr/bin/id -u)"
          dir="/tmp/user-$uid"
          /bin/mkdir -p "$dir"
          /bin/chmod 700 "$dir"
          # Runs as your user, so owner is already correct.
          /bin/launchctl setenv XDG_RUNTIME_DIR "$dir"
        '';
      in
      {
        enable = true;
        config = {
          Label = "dev.user.set-xdg-runtime-dir";
          ProgramArguments = [ (lib.getExe' setXdgRuntime "hm-set-xdg-runtime") ];
          RunAtLoad = true; # set on login
          KeepAlive = false;
          ProcessType = "Background";
          # StandardOutPath = "${config.xdg.stateHome}/xdg-runtime.out";
          # StandardErrorPath = "${config.xdg.stateHome}/xdg-runtime.err";
        };
      };
  };

  # TODO: write linux based module to set XDG_RUNTIME_DIR
  home.sessionVariables =
    lib.mkIf (isDarwin && ((args ? darwinConfig) || (uid != null)))
      {
        XDG_RUNTIME_DIR =
          let
            final_uid = args.darwinConfig.users.users.${config.home.username}.uid or uid;
          in
          "/tmp/user-${toString final_uid}";
      };
}
