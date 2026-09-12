# Python dependencies shared by local and sandboxed behavior tests.
{ pkgs }:
pkgs.python3.withPackages (ps: [
  ps.pytest
  ps.pytest-timeout
  ps.tomlkit
  ps.uharfbuzz
])
