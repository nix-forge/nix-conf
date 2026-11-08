# shellcheck shell=bash
# The Nix builder supplies out.
# shellcheck disable=SC2154
read -r -a compile_flags <<<"$(pkg-config --cflags --libs Qt6Gui pangocairo)"
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
export QT_QPA_PLATFORM=offscreen
export QT_PLUGIN_PATH=@pkgs_qt6_qtbase@/lib/qt-6/plugins
mkdir -p "$out" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
c++ -fPIC -std=c++17 -Wall -Wextra -Wpedantic -Wconversion \
  -Wsign-conversion -Werror @tests_fonts_render_native_cpp@ \
  -o render "${compile_flags[@]}"
./render "$out"
