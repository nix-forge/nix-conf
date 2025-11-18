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
    if pkgs.stdenv.hostPlatform.isLinux then defaultConfigDirLinux else defaultConfigDirDarwin;
  xdgConfigDir = "${config.xdg.configHome}/nushell";
  symlinkConfig = config.xdg.enable && (xdgConfigDir != defaultConfigDir);
in
{
  # Symlink the XDG config directory to the default config directory if not the same
  # NOTE: this is due to NuShell nix only setting the XDG_CONFIG_DIR env var through bash and zsh shells
  home.file.${defaultConfigDir} = lib.mkIf symlinkConfig {
    source = config.lib.file.mkOutOfStoreSymlink xdgConfigDir;
  };
}
