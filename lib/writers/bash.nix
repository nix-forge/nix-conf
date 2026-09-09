{ lib, ... }: {
  writeBashTemplate =
    { pkgs }:
    {
      name,
      src,
      replacements,
      dir ? null,
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
      rendered = pkgs.replaceVarsWith {
        name = "${name}-body";
        inherit src replacements;
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
