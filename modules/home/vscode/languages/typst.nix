{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  extensions = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
in
{
  programs.vscode.profiles.default = {
    extensions = extensions.forVscode [ "myriad-dreamin.tinymist" ];

    userSettings = {
      "[typst]" = {
        "editor.tabSize" = 2;
      };

      "tinymist.formatterIndentSize" = 2;
      "tinymist.formatterMode" = "typstyle";

      "tinymist.lint.enabled" = true;
      "tinymist.lint.when" = "onType";

      "tinymist.outputPath" = "$root/target/$dir/$name";

      "tinymist.exportPdf" = "onSave";

      "tinymist.serverPath" = lib.getExe pkgs.tinymist;
    };
  };

  home.packages = [ pkgs.typst ];
}
