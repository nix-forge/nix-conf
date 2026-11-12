{ config, ... }:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [ "mathworks.language-matlab" ];

    # MATLAB installation/licensing and runtime connections remain user-owned.
    userSettings = {
      # Formatter schema values preserve the publisher's manifest casing.
      "[matlab]"."editor.defaultFormatter" = "MathWorks.language-matlab";
      "MATLAB.telemetry" = false;
      "MATLAB.matlabConnectionTiming" = "onDemand";
    };
  };
}
