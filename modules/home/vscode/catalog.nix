{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vscode;
  catalog = (pkgs.extend inputs.nix4vscode.overlays.default).nix4vscode;
  packageVersion = if cfg.package == null then null else cfg.package.version or null;
in
{
  options.programs.vscode.extensionCompatibilityVersion = lib.mkOption {
    type = lib.types.str;
    default = if packageVersion == null then pkgs.vscode.version else packageVersion;
    defaultText = lib.literalExpression "programs.vscode.package.version or pkgs.vscode.version";
    description = ''
      Editor version used to select compatible stable catalog extensions.
      Set this explicitly for an externally installed or unversioned editor;
      those cases otherwise use the pinned Nixpkgs VS Code version.
    '';
  };

  config = {
    lib.vscode.catalogExtensions =
      extensionIds: catalog.forVscodeVersion cfg.extensionCompatibilityVersion extensionIds;

    assertions = lib.mkIf cfg.enable [
      {
        assertion = cfg.extensionCompatibilityVersion != "";
        message = "VS Code extensionCompatibilityVersion must name an editor version.";
      }
    ];
  };
}
