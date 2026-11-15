# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR/home" OPEN_LOG="$TMPDIR/urls" BROWSER=@browser@
mkdir -p "$HOME"
export DISPLAY=:99 XDG_CURRENT_DESKTOP=generic
@opener_actual_open@/bin/actual-open
printf '%s\n' http://127.0.0.1:41831 >expected
cmp expected "$OPEN_LOG"
touch "$out"
