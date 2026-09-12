# Import dependencies shared by sandboxed Python checks and local type-check hooks.
{ pkgs }:
pkgs.python3.withPackages (
  ps:
  with ps;
  [
    dbus-next
    fonttools
    hypothesis
    lxml
    mkdocs
    pillow
    pygments
    pytest
    selenium
    tomlkit
    uharfbuzz
    websocket-client
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pyudev ]
)
