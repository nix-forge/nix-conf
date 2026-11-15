{
  lib,
  config,
  pkgs,
  ...
}:
let
  catalogExtensions = config.lib.vscode.catalogExtensions;
in
{
  imports = [ ../default.nix ];
  programs.vscode.profiles.default = {
    # Retain the newer Python client. Interpreters stay project-owned and
    # ty/Ruff use explicit Nix executables below; no implicit Pylance pack.
    extensions = catalogExtensions [
      "ms-python.python"
      "ms-python.debugpy"

      "charliermarsh.ruff"
      "astral-sh.ty"

    ];

    userSettings = {
      "[python]" = {
        "editor.tabSize" = 4;
        "editor.defaultFormatter" = "charliermarsh.ruff";
        "editor.formatOnSaveMode" = "file";
        "editor.codeActionsOnSave" = {
          "source.fixAll.ruff" = "explicit";
          "source.organizeImports.ruff" = "explicit";
        };
      };

      "notebook.formatOnSave.enabled" = false;
      "notebook.codeActionsOnSave" = {
        "notebook.source.fixAll.ruff" = "explicit";
        "notebook.source.organizeImports.ruff" = "explicit";
      };

      "ruff.path" = [ (lib.getExe pkgs.ruff) ];
      "ty.path" = [ (lib.getExe pkgs.ty) ];
      # Project Ruff configuration owns lint rules; do not hide diagnostics globally.
      "ruff.configurationPreference" = "filesystemFirst";
      "python.languageServer" = "None"; # using ty instead

      "python.terminal.activateEnvironment" = !config.programs.direnv.enable;
    };
  };
}
