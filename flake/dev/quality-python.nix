# Import dependencies shared by sandboxed Python checks and local type-check hooks.
{ pkgs }:
pkgs.python3.withPackages (
  ps:
  with ps;
  [
    (import ../../lib/python/notification-process/package.nix { inherit pkgs; })
    dbus-next
    defusedxml
    fonttools
    hypothesis
    lxml
    mkdocs
    pillow
    pygments
    (pygobject-stubs.overridePythonAttrs (old: {
      env = (old.env or { }) // {
        # The GTK probe requires Gtk 3; the default stubs describe Gtk 4.
        PYGOBJECT_STUB_CONFIG = "Gtk3,Gdk3";
      };
    }))
    pytest
    pytest-timeout
    pyyaml
    selenium
    tomlkit
    uharfbuzz
    watchdog
    websocket-client
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    # Converting the application enables Python module metadata checks. Patch
    # its placeholder project version using the supported Nixpkgs hook.
    (ps.toPythonModule (
      pkgs.nixos-test-driver.overridePythonAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ ps.pyprojectVersionPatchHook ];
      })
    ))
    libvirt
    pygobject3
    pyudev
  ]
)
