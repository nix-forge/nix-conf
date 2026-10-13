{ lib, ... }: {
  reason = "Home Manager passes a removed hyprland argument to the selected portal package.";
  upstream = "https://github.com/nix-community/home-manager/blob/acd21c5a3420a9d5fd0ed06299b10828267ef9ba/modules/services/window-managers/hyprland/default.nix";
  removal = "Home Manager checks the portal override arguments before passing hyprland.";
  reviewedRevision = "acd21c5a3420a9d5fd0ed06299b10828267ef9ba";
  inputPath = [ "home-manager" ];
  apply =
    package:
    if lib.functionArgs package.override ? hyprland then
      package
    else
      lib.extendDerivation true {
        # The selected portal links its own shared libraries and no longer takes
        # a compositor package. Preserve all remaining package override arguments.
        override = lib.setFunctionArgs (
          args:
          package.override (
            if builtins.isFunction args then
              old: removeAttrs (args old) [ "hyprland" ]
            else
              removeAttrs args [ "hyprland" ]
          )
        ) (lib.functionArgs package.override);
      } package;
}
