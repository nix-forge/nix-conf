#!/usr/bin/env bash
set -eu
base=$1
shift
for name in "$@"; do
  p=$base/$name
  test -f "$p" && test -r "$p" || {
    printf 'MISSING\t%s\n' "$name"
    exit 20
  }
  printf '%s\t' "$name"
  base64 -w0 "$p"
  printf '\n'
done
