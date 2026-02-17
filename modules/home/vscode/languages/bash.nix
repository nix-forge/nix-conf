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
    extensions = extensions.forVscode [
      "mads-hartmann.bash-ide-vscode"
      "timonwong.shellcheck"
      "foxundermoon.shell-format"
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
