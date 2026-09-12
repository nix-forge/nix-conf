# Python dependencies shared by local and sandboxed behavior tests.
{ pkgs }:
pkgs.python3.withPackages (
  ps:
  [
    ps.dbus-next
    ps.hypothesis
    ps.pytest
    ps.pytest-timeout
    ps.tomlkit
    ps.uharfbuzz
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ps.pyudev ]
)
