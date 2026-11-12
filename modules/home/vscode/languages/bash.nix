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
    extensions = catalogExtensions [ "mads-hartmann.bash-ide-vscode" ];

    userSettings = {
      "[shellscript]" = {
        "editor.tabSize" = 2;
        "editor.insertSpaces" = true;
        "editor.defaultFormatter" = "mads-hartmann.bash-ide-vscode";
      };

      "bashIde.shellcheckPath" = lib.getExe pkgs.shellcheck;
      "bashIde.shfmt.path" = lib.getExe pkgs.shfmt;
      # Respect project .editorconfig; these options match the existing shell style.
      "bashIde.shfmt.binaryNextLine" = true;
      "bashIde.shfmt.caseIndent" = true;
      "bashIde.shfmt.spaceRedirects" = true;
      "bashIde.shfmt.simplifyCode" = true;
    };
  };
}
