{
  lib,
  pkgs,
  config,
  ...
}:
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

  launchd.agents =
    lib.mkIf
      (
        isDarwin
        && config.xdg.enable
        && (config.home.uid != null)
        && (builtins.hasAttr "XDG_RUNTIME_DIR" config.home.sessionVariables)
      )
      {
        make-xdg-runtime-dir =
          let
            makeXdgRuntimeDir = pkgs.writeShellScript "hm-make-xdg-runtime-dir" ''
              set -euo pipefail
              /bin/mkdir -p "${config.home.sessionVariables.XDG_RUNTIME_DIR}"
              /bin/chmod 700 "${config.home.sessionVariables.XDG_RUNTIME_DIR}"
              /bin/launchctl setenv XDG_RUNTIME_DIR "${config.home.sessionVariables.XDG_RUNTIME_DIR}"
            '';
          in
          {
            enable = true;
            config = {
              Label = "dev.user.hm-make-xdg-runtime-dir";
              ProgramArguments = [ (lib.getExe' makeXdgRuntimeDir "hm-make-xdg-runtime-dir") ];
              RunAtLoad = true;
              KeepAlive = false;
              ProcessType = "Background";
            };
          };
      };

  home.sessionVariables.XDG_RUNTIME_DIR =
    lib.mkIf (config.home.uid != null)
      "/${if isLinux then "run" else "tmp"}/user/${toString config.home.uid}";
}
