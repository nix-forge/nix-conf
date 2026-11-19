_: {
  mkGtkCssChecker =
    { pkgs }:
    # Shared GTK 4 parser package for the desktop stylesheet consumers.
    (import ../../flake/runtime-packages.nix { inherit pkgs; }).gtkCssChecker;
}
