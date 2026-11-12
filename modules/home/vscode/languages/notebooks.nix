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
  imports = [ ./python.nix ];
  # Same upstream version as the catalog, with immutable-store metadata and
  # writable-temp fixes. Keep optional pack members explicit.
  # The curated 2025.9.1 manifest requires ^1.105.0. Keep this floor in
  # review when updating its package; catalog filtering cannot repair it.
  assertions = [
    {
      assertion = lib.versionAtLeast config.programs.vscode.extensionCompatibilityVersion "1.105.0";
      message = "The curated Jupyter extension requires VS Code >= 1.105.0; use a compatible editor or omit vscode-languages-notebooks.";
    }
  ];
  programs.vscode.profiles.default.extensions = [
    pkgs.vscode-extensions.ms-toolsai.jupyter
  ]
  ++ catalogExtensions [ "ms-toolsai.jupyter-renderers" ];
}
