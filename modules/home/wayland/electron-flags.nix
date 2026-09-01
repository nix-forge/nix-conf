{ config, ... }: {
  home.file."${config.xdg.configHome}/electron-flags.conf".source = ./electron-flags.conf;
}
