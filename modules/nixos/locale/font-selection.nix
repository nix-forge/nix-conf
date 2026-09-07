{ config, lib, ... }: {
  fonts.fontconfig.localConf = lib.mkIf config.fonts.fontconfig.enable (
    builtins.readFile ../../shared/font-selection.conf
  );
}
