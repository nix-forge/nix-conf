{ config, lib, ... }: {
  imports = [ ./default.nix ];
  home.sessionVariables.TERMINAL = lib.mkDefault (
    if config.programs.ghostty.package == null then
      "ghostty"
    else
      lib.getExe config.programs.ghostty.package
  );
}
