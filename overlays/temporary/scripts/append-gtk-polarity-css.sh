# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
for stylesheet in "$out"/gtk-{3,4}.0/gtk.css "$out"/gtk-{3,4}.0/gtk-dark.css "$out"/gtk-{3,4}.0/gtk-light.css; do
  if [ -f "$stylesheet" ]; then
    cat "${finalCss}" >>"$stylesheet"
  fi
done
