# Keep the shared helper interface explicit. Adding a file beside a helper must
# not import it or silently replace an existing export.
{ lib }:
{
  dir = {
    inherit (import ./dir/collect.nix { inherit lib; }) collectBySuffix;
  };

  desktop = {
    inherit (import ./desktop/gtk-css-check.nix { inherit lib; }) mkGtkCssChecker;
  };

  writers = {
    inherit (import ./writers/bash.nix { inherit lib; }) writeBashTemplate;
    inherit (import ./writers/lua.nix { inherit lib; }) checkLuaFile;
    inherit (import ./writers/nushell.nix { inherit lib; }) checkNuFile;
    inherit (import ./writers/powershell.nix { inherit lib; }) writePowerShell;
  };
}
