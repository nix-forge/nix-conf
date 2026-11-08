# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
printf '%s\n' '* { color: #123456; }' >valid.css
@cssChecker@/bin/check-gtk-css valid.css
printf '%s\n' '* { color: this-is-not-a-color; }' >invalid.css
if @cssChecker@/bin/check-gtk-css invalid.css; then
  echo "GTK CSS parser accepted invalid CSS" >&2
  exit 1
fi
if @cssChecker@/bin/check-gtk-css missing.css; then
  echo "GTK CSS parser accepted a missing file" >&2
  exit 1
fi
printf '%s\n' '@import url("missing.css");' >missing-import.css
if @cssChecker@/bin/check-gtk-css missing-import.css; then
  echo "GTK CSS parser accepted a missing import" >&2
  exit 1
fi
touch "$out"
