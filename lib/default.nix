# Keep the shared helper interface explicit. Adding a file beside a helper must
# not import it or silently replace an existing export.
{ lib }: {
  dir = { inherit (import ./dir/collect.nix { inherit lib; }) collectBySuffix; };

  desktop = {
    inherit (import ./desktop/gtk-css-check.nix { inherit lib; }) mkGtkCssChecker;
    resolveHyprlandPackage = import ./desktop/hyprland-package.nix;
  };

  systemd.execArgs = import ./systemd/exec-args.nix;

  templates.renderText = import ./templates/text.nix;

  writers = {
    inherit (import ./writers/bash.nix { inherit lib; })
      checkedShellText
      renderBashText
      writeBashTemplate
      writeShellApplication
      writeShellScript
      writeShellScriptBin
      ;
    inherit (import ./writers/lua.nix { inherit lib; }) checkLuaFile;
    inherit (import ./writers/nushell.nix { inherit lib; }) checkNuFile;
    inherit (import ./writers/powershell.nix { inherit lib; }) writePowerShell;
  };
}
