_: {
  mkGtkCssChecker =
    { pkgs }:
    # All current desktop stylesheet consumers use GTK 4 in the locked package set.
    pkgs.runCommandCC "check-gtk-css"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.gtk4 ];
      }
      ''
        mkdir -p "$out/bin"
        $CC -Wall -Wextra -Werror ${./check-gtk-css.c} $(pkg-config --cflags --libs gtk4) -o "$out/bin/check-gtk-css"
      '';
}
