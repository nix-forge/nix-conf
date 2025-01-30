{ pkgs, ... }:
let
  python-pkg = pkgs.python3;
  my-python = python-pkg.withPackages (
    ps: with ps; [
      black
    ]
  );
in
{
  home.packages = [ my-python ];
}
