{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;

  inherit (config.home) uid;
  uidStr = toString uid;

  darwinBase = "/private/tmp";
  xdgRuntimeDir =
    if isLinux then
      "/run/user/${uidStr}"
    else
      "${darwinBase}/xdg-runtime-${uidStr}";

  ensureDarwinRuntimeApp = pkgs.writeShellApplication {
    name = "hm-ensure-xdg-runtime-dir";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail
      dir='${xdgRuntimeDir}'

      # Create securely: private to the user, no group/other perms.
      umask 077

      # Refuse to operate on symlinks (basic hardening).
      if [ -L "$dir" ]; then
        echo "Refusing: XDG_RUNTIME_DIR path is a symlink: $dir" >&2
        exit 1
      fi

      mkdir -p "$dir"
      chmod 700 "$dir"

      # Sanity checks required by the XDG runtime dir expectations (0700, user-owned).
      if [ ! -d "$dir" ]; then
        echo "Refusing: XDG_RUNTIME_DIR is not a directory: $dir" >&2
        exit 1
      fi
      if [ ! -O "$dir" ]; then
        echo "Refusing: XDG_RUNTIME_DIR is not owned by the current user: $dir" >&2
        exit 1
      fi

      # Make it available to GUI apps / launchd-spawned processes (shell-independent).
      /bin/launchctl setenv XDG_RUNTIME_DIR "$dir"
    '';
  };
in
lib.mkMerge [
  {
    #### XDG base dirs (safe + deterministic)
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

    home.sessionVariables = lib.mkIf (uid != null) {
      XDG_RUNTIME_DIR = xdgRuntimeDir;
    };

    home.activation.ensureXdgRuntimeDir = lib.mkIf (isDarwin && uid != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.getExe ensureDarwinRuntimeApp}
      ''
    );

    launchd.agents.ensure-xdg-runtime-dir = lib.mkIf (isDarwin && uid != null) {
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
  (lib.mkIf (lib.hasAttr "age" config) {
    age = {
      secretsDir = "${config.xdg.configHome}/agenix";
      secretsMountPoint = "${xdgRuntimeDir}/agenix.d";
    };
  })
]
