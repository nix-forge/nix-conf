# shellcheck shell=bash
read -r -a compile_flags <<<"$(pkg-config --cflags --libs gtk4)"
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out/bin"
$CC -Wall -Wextra -Werror @check_gtk_css_c@ "${compile_flags[@]}" -o "$out/bin/check-gtk-css"
