{ lib, ... }: {
  writeBashTemplate =
    { pkgs }:
    {
      name,
      src,
      replacements,
      dir ? null,
      runtimeInputs ? [ ],
      inheritPath ? true,
      shellcheckFlags ? [ ],
    }:
    let
      check = pkgs.writeShellApplication {
        name = "check-rendered-bash";
        text = ''
          ${pkgs.stdenv.shellDryRun} "$1"
          ${lib.getExe pkgs.shellcheck-minimal} --shell=bash ${lib.escapeShellArgs shellcheckFlags} "$1"
        '';
      };
      contextualReplacements = lib.mapAttrs (
        _: value: if builtins.isPath value then "${value}" else value
      ) replacements;
      runtimePath = lib.makeBinPath runtimeInputs;
      pathSetup =
        if inheritPath then
          lib.optionalString (runtimeInputs != [ ]) "export PATH=${lib.escapeShellArg runtimePath}:\"$PATH\""
        else
          "export PATH=${lib.escapeShellArg runtimePath}";
      rendered = pkgs.replaceVarsWith {
        name = "${name}-body";
        inherit src;
        replacements = contextualReplacements;
        # The writer supplies the interpreter. Keep standalone source files
        # usable, but remove their known Bash shebang after strict substitution.
        postInstall = ''
          IFS= read -r firstLine < "$target" || true
          case "$firstLine" in
            '#!${lib.getExe pkgs.bash}'|'#!${lib.getExe pkgs.bashNonInteractive}'|'#!${pkgs.runtimeShell}'|'#!/usr/bin/env bash'|'#!/bin/bash')
              tail -n +2 "$target" > "$TMPDIR/script-body"
              cat "$TMPDIR/script-body" > "$target"
              ;;
            '#!'*)
              echo "writeBashTemplate requires a Bash source without interpreter arguments" >&2
              exit 1
              ;;
          esac
          ${lib.optionalString (pathSetup != "") ''
            {
              printf '%s\n' ${lib.escapeShellArg pathSetup}
              cat "$target"
            } > "$TMPDIR/script-with-runtime-path"
            cat "$TMPDIR/script-with-runtime-path" > "$target"
          ''}
        '';
      };
      options.check = lib.getExe check;
    in
    # Pass the derivation itself: interpolating it would turn its path into
    # literal program text. The writer reads it and checks the complete script.
    if dir == "bin" then
      pkgs.writers.writeBashBin name options rendered
    else
      pkgs.writers.writeBash (if dir == null then name else "/${dir}/${name}") options rendered;
}
