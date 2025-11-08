{ pkgs, ... }:
let
  python-pkg = pkgs.python3;
  my-python = python-pkg.withPackages (
    ps: with ps; [
      requests
      numpy
      black
      mypy
    ]
  );
in
{
  home.packages = [
    my-python

    pkgs.uv
    pkgs.ruff
  ];
}
