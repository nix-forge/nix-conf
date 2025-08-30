profileName:
{ lib, pkgs, ... }@args:
let
  extensions = pkgs.callPackage ../marketplace.nix args;
in
{
  programs.vscode.profiles.${profileName} = {
    extensions = with extensions.preferNixpkgsThenPreRelease; [
      mads-hartmann.bash-ide-vscode
      timonwong.shellcheck
      foxundermoon.shell-format
    ];

    userSettings = {
      "[shellscript]" = {
        "editor.tabSize" = 2;
        "editor.insertSpaces" = false;
      };

      "shellcheck.executablePath" = lib.getExe pkgs.shellcheck;
      "shellformat.path" = lib.getExe pkgs.shfmt;
      "shellformat.flag" = lib.concatStringsSep " " [
        "--indent 0"
        "--binary-next-line"
        "--switch-case-indent"
        "--space-redirects"
        "--keep-padding"
      ];
    };
  };
}
