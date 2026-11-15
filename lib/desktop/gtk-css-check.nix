_: {
  mkGtkCssChecker =
    { pkgs }:
    # All current desktop stylesheet consumers use GTK 4 in the locked package set.
    pkgs.runCommandCC "check-gtk-css"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.gtk4 ];
      }
      (
        (import ../templates/text.nix) ./scripts/build-gtk-css-checker.sh {
          check_gtk_css_c = ./check-gtk-css.c;
        }
      );
}
