# shellcheck shell=bash
# replaceVarsWith supplies target and TMPDIR to this build hook.
# shellcheck disable=SC2154
IFS= read -r firstLine <"$target" || true
case "$firstLine" in
'#!@bash@' | '#!@bashNonInteractive@' | '#!@runtimeShell@' | '#!/usr/bin/env bash' | '#!/bin/bash')
  tail -n +2 "$target" >"$TMPDIR/script-body"
  cat "$TMPDIR/script-body" >"$target"
  ;;
'#!'*)
  echo "writeBashTemplate requires a Bash source without interpreter arguments" >&2
  exit 1
  ;;
esac
path_setup=@pathSetup@
if [[ -n $path_setup ]]; then
  {
    printf '%s\n' "$path_setup"
    cat "$target"
  } >"$TMPDIR/script-with-runtime-path"
  cat "$TMPDIR/script-with-runtime-path" >"$target"
fi
