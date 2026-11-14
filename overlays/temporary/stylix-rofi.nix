{ lib, ... }: {
  reason = "Stylix's Rofi target defines the renamed programs.rofi.font option.";
  upstream = "https://github.com/nix-community/stylix/pull/2501";
  removal = "Stylix uses programs.rofi.settings.font and the Home Manager profile evaluates without the rename warning.";
  reviewedRevision = "3e27b6c499e507df6e3bb8eca3614f5c95e28140";
  inputPath = [ "stylix" ];
  apply =
    stylix:
    let
      target = stylix + "/modules/rofi/hm.nix";
      source = builtins.readFile target;
      oldOption = "programs.rofi.font =";
      patchedTarget = builtins.toFile "stylix-rofi.nix" (
        assert lib.assertMsg (lib.hasInfix oldOption source)
          "Stylix no longer defines the expected deprecated Rofi option";
        builtins.replaceStrings [ oldOption ] [ "programs.rofi.settings.font =" ] source
      );
      mkTarget = import (stylix + "/stylix/mk-target.nix") {
        name = "rofi";
        humanName = "Rofi";
      };
    in
    {
      disabledModules = [ target ];
      imports = [ ({ config, lib, ... }: (import patchedTarget) { inherit config lib mkTarget; }) ];
    };
}
