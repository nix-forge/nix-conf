{ lib, ... }: {
  reason = "Stylix's nvf target defines the deprecated lualine.theme option.";
  upstream = "https://github.com/nix-community/stylix/blob/master/modules/neovim/nvf.nix";
  removal = "Stylix uses lualine.setupOpts.options.theme and nvf evaluates without the rename warning.";
  reviewedRevision = "5e3809851f486e7fc7e84b40f174c74b60ecc784";
  inputPath = [ "stylix" ];
  apply =
    stylix:
    let
      targetDirectory = stylix + "/modules/neovim";
      source = builtins.readFile (targetDirectory + "/nvf.nix");
      oldOption = "lualine.theme =";
      patchedTarget = builtins.toFile "stylix-nvf.nix" (
        assert lib.assertMsg (lib.hasInfix oldOption source)
          "Stylix no longer defines the expected deprecated nvf option";
        builtins.replaceStrings [ oldOption ] [ "lualine.setupOpts.options.theme =" ] source
      );
      mkTarget = import (stylix + "/stylix/mk-target.nix") {
        name = "neovim";
        humanName = "Neovim";
      };
    in
    {
      # Stylix's importApply children have no stable module keys. Replace their
      # keyed parent, preserving all its other targets and nvf's target options.
      disabledModules = [ (targetDirectory + "/hm.nix") ];
      imports = map (module: lib.modules.importApply module mkTarget) [
        (targetDirectory + "/neovim.nix")
        (targetDirectory + "/neovide.nix")
        (targetDirectory + "/nixvim.nix")
        patchedTarget
        (targetDirectory + "/vim.nix")
      ];
    };
}
