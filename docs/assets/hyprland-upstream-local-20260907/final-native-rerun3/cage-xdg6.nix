let
  pkgs = import (builtins.getFlake "nixpkgs").outPath {};
in
pkgs.cage.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace cage.c \
      --replace-fail "wlr_xdg_shell_create(server.wl_display, 5)" \
      "wlr_xdg_shell_create(server.wl_display, 6)"
  '';
})
