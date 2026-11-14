{
  config,
  lib,
  pkgs,
  ...
}:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [ "myriad-dreamin.tinymist" ];

    userSettings = {
      "[typst]" = {
        "editor.defaultFormatter" = "myriad-dreamin.tinymist";
        "editor.tabSize" = 2;
      };

      "tinymist.formatterIndentSize" = 2;
      "tinymist.formatterMode" = "typstyle";
      "tinymist.formatterPrintWidth" = 80;

      "tinymist.lint.enabled" = true;
      "tinymist.lint.when" = "onSave";

      "tinymist.outputPath" = "$root/target/$dir/$name";

      "tinymist.exportPdf" = "never";

      "tinymist.serverPath" = lib.getExe pkgs.tinymist;
    };
  };
}
