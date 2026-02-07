profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.release; [
      mads-hartmann.bash-ide-vscode
      timonwong.shellcheck
      foxundermoon.shell-format
    ];

    userSettings = {
      "[shellscript]" = {
        "editor.tabSize" = 2;
        "editor.insertSpaces" = false;
        "editor.defaultFormatter" = "foxundermoon.shell-format";
      };

      "shellcheck.executablePath" = lib.getExe pkgs.shellcheck;
      "shellformat.path" = lib.getExe pkgs.shfmt;
      "shellformat.flag" = lib.concatStringsSep " " [
        "--indent 0"
        "--binary-next-line"
        "--case-indent"
        "--space-redirects"
        "--keep-padding"
        "--simplify"
      ];
    };
  };
}
