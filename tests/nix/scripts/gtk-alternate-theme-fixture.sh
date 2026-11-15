# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/share/themes"
cp -r @pkgs_adw_gtk3@/share/themes/adw-gtk3 "$out/share/themes/alternate-theme"
chmod -R u+w "$out/share/themes/alternate-theme"
cp "$out/share/themes/alternate-theme/gtk-3.0/gtk.css" \
  "$out/share/themes/alternate-theme/gtk-3.0/gtk-light.css"
