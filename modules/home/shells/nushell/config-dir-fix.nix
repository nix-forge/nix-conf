{
  config,
  pkgs,
  lib,
  ...
}:
let
  defaultConfigDirDarwin = "${config.home.homeDirectory}/Library/Application Support/nushell";
  defaultConfigDirLinux = "${config.home.homeDirectory}/.config/nushell";
  defaultConfigDir =
    if pkgs.stdenv.hostPlatform.isLinux then
      defaultConfigDirLinux
    else
      defaultConfigDirDarwin;
  desiredConfigDir = config.programs.nushell.configDir;
  symlinkConfig = desiredConfigDir != defaultConfigDir;
in
{
  # Symlink the desired config directory to the default config directory if not the same
  home.file.${defaultConfigDir} = lib.mkIf symlinkConfig {
    source = config.lib.file.mkOutOfStoreSymlink desiredConfigDir;
  };
}
