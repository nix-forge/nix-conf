{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.codex;
  base = pkgs.codex;
  codexHome = config.programs.chatgpt.codexHome;
  launcher = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "codex";
    dir = "bin";
    src = ./scripts/codex-home.sh.in;
    replacements = {
      codex = lib.escapeShellArg (lib.getExe base);
      defaultHome = lib.escapeShellArg codexHome;
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
