{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.codex;
  base = pkgs.codex-latest;
  codexHome = config.programs.chatgpt.codexHome;
  desktopApp =
    if pkgs.stdenv.hostPlatform.isDarwin && config.programs.chatgpt ? darwinBundle then
      "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/${config.programs.chatgpt.darwinBundle}"
    else
      "";
  launcher = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "codex";
    dir = "bin";
    src = ./scripts/codex-home.sh.in;
    replacements = {
      codex = lib.escapeShellArg (lib.getExe base);
      defaultHome = lib.escapeShellArg codexHome;
      desktopApp = lib.escapeShellArg desktopApp;
    };
  };
in
{
  imports = [ ../agentic-gui/codex/settings.nix ];
  config = lib.mkIf cfg.enable {
    programs.codex.package = pkgs.symlinkJoin {
      name = "codex-configured-${base.version}";
      inherit (base) version meta;
      paths = [ base ];
      postBuild = ''
        rm "$out/bin/codex"
        ln -s ${launcher}/bin/codex "$out/bin/codex"
      '';
      passthru.unwrapped = base;
    };
  };
}
