{
  config,
  pkgs,
  lib,
  ...
}:
{
  # This fallback is an application dependency, even with no design collection.
  home.packages = lib.optionals (config.typography.designLibrary == "none") [
    (pkgs.google-fonts.override { fonts = [ "Iosevka Charon Mono" ]; })
  ];
  imports = [
    ./settings.nix
    ./keybinds.nix
  ];
  programs.vscode = {
    enable = true;
    mutableExtensionsDir = false;
    profiles.default = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;
    };
  };
}
