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
  programs.vscode.profiles.default = {
    extensions = catalogExtensions [
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "oxc.oxc-vscode"
    ];
    userSettings = {
      "prettier.requireConfig" = true;
      "prettier.resolveGlobalModules" = false;
      "oxc.requireConfig" = true;
      # Oxfmt has its own client and is not gated by requireConfig.
      "oxc.enable.oxfmt" = false;
      "oxc.path.oxfmt" = lib.getExe pkgs.oxfmt;
      "oxc.path.oxlint" = lib.getExe pkgs.oxlint;
      "eslint.run" = "onSave";
      "oxc.lint.run" = "onSave";
    };
  };
}
