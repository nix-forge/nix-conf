{
  lib,
  pkgs,
  config,
  ...
}:
assert config.home.uid != null "home.uid must be set to use the xdg module";
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  xdgRuntimeDir =
    let
      uid = toString config.home.uid;
    in
    if isDarwin then "/private/tmp/xdg-runtime-${uid}" else "/run/user/${uid}";

  ensureDarwinRuntimeApp = pkgs.replaceVarsWith {
    name = "hm-ensure-xdg-runtime-dir";
    src = ./ensure-xdg-runtime-dir.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      inherit xdgRuntimeDir;
      inherit (config.home) username;
    };
  };
in
{
  xdg = {
    enable = true;

    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
    cacheHome = "${config.home.homeDirectory}/.cache";

    userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        PROJECTS = "${config.home.homeDirectory}/Projects";
        RUNTIME = xdgRuntimeDir;
      };
    };
  };

  home.preferXdgDirectories = config.xdg.enable;

  home.activation.ensureXdgRuntimeDir = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${lib.getExe ensureDarwinRuntimeApp}
    ''
  );
  launchd.agents.ensure-xdg-runtime-dir = {
    enable = true;
    config = {
      Label = "dev.user.hm-ensure-xdg-runtime-dir";
      ProgramArguments = [ (lib.getExe ensureDarwinRuntimeApp) ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Background";
    };
  };
}
