{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  base = pkgs.codex;
  # Keep standalone calls on the same state directory as the desktop and T3,
  # including processes that do not inherit Home Manager's session variables.
  launcher = (myLib.writers.writeBashTemplate { inherit pkgs; }) {
    name = "codex";
    dir = "bin";
    text = ''
      #!/usr/bin/env bash
      # shellcheck shell=bash
      set -euo pipefail
      if [[ -z ''${CODEX_HOME:-} ]]; then
        # The configured directory is literal, including any dollar signs.
        # shellcheck disable=SC2016
        export CODEX_HOME=@defaultHome@
      fi
      if [[ ''${CODEX_INTERNAL_ORIGINATOR_OVERRIDE:-} == "T3 Code" ]]; then
        exec @codex@ \
          -c 'plugins."codex-app-tools@openai-bundled".enabled=false' \
          "$@"
      fi
      exec @codex@ "$@"
    '';
    replacements = {
      codex = lib.escapeShellArg (lib.getExe base);
      defaultHome = lib.escapeShellArg config.programs.chatgpt.codexHome;
    };
  };
in
{
  imports = [ ../agentic-gui/codex/plugins.nix ];

  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];
  programs.codex = {
    enable = true;
    package = lib.mkIf config.programs.codex.enable (
      pkgs.symlinkJoin {
        name = "codex-configured-${base.version}";
        inherit (base) version meta;
        paths = [ base ];
        postBuild = ''
          rm "$out/bin/codex"
          ln -s ${launcher}/bin/codex "$out/bin/codex"
        '';
        passthru.unwrapped = base;
      }
    );
  };
}
