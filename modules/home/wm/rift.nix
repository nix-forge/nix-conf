{
  config,
  lib,
  inputs,
  ...
}:
let
  ocr = config.macos.ocrCapture;
  modifiers = {
    cmd = "Meta";
    alt = "Alt";
    ctrl = "Ctrl";
    shift = "Shift";
  };
  ocrShortcut = lib.concatMapStringsSep " + " (key: modifiers.${key} or (lib.toUpper key)) (
    lib.splitString "-" ocr.shortcuts.copyRegion
  );
in
{
  imports = [
    inputs.nixpkgs-personal.homeManagerModules.rift
    ../macos/application-capabilities.nix
    ../macos/applications.nix
    ../macos/ocr-capture.nix
  ];

  config = lib.mkIf config.programs.rift.enable {
    programs.rift.settings.keys = lib.mkIf (ocr.enable && ocr.shortcuts.copyRegion != null) {
      ${ocrShortcut}.exec = ocr.command;
    };

    macos.applicationCapabilities.apps.rift = {
      enable = true;
      bundle = "Rift.app";
      bundleId = "git.acsandmann.rift";
      features.windowManagement = {
        enable = true;
        service = "accessibility";
        reason = "Manage windows and workspaces using Rift";
        source = "https://github.com/acsandmann/rift/blob/2bb6647a18cde9ac44470d296988298c1093460d/src/sys/accessibility.rs";
        instruction = "Move and focus a harmless window using Rift's configured shortcuts.";
      };
    };
  };
}
