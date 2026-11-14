# Python dependencies shared by local and sandboxed behavior tests.
{ pkgs }:
pkgs.python3.withPackages (
  ps:
  [
    (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
    ps.dbus-next
    ps.defusedxml
    ps.hypothesis
    ps.pillow
    ps.pytest
    ps.pytest-timeout
    ps.tomlkit
    ps.uharfbuzz
    ps.watchdog
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    ps.libvirt
    ps.pyudev
  ]
)
