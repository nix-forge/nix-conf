{ config, lib, ... }:
let
  cfg = config.macos.dictation;
in
{
  options.macos.dictation.enable = lib.mkEnableOption "macOS Dictation on the Fn/Globe key";

  config = lib.mkIf cfg.enable {
    # Dictation itself and its privacy choices require user consent in System Settings.
    # This supported default only assigns a shortcut after Dictation is enabled.
    system.defaults.hitoolbox.AppleFnUsageType = "Start Dictation";
  };
}
