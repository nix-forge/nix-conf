# shellcheck shell=bash
read -r -a compile_flags <<<"$(pkg-config --cflags --libs wayland-client)"
runHook preBuild
protocol=@pkgs_wayland_protocols@/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header "$protocol" xdg-shell-client-protocol.h
wayland-scanner private-code "$protocol" xdg-shell-protocol.c
cc -D_GNU_SOURCE -Wall -Wextra -Werror -I. \
  @subsurface_rounding_client_c@ xdg-shell-protocol.c \
  "${compile_flags[@]}" -o subsurface-rounding-client
runHook postBuild
