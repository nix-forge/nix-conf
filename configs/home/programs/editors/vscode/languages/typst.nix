profileName:
{ pkgs, lib, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [ myriad-dreamin.tinymist ];

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
