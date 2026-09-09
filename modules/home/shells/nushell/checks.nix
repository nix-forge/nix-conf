{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nushell;
  generatedFiles =
    builtins.filter
      (
        name:
        builtins.hasAttr "${cfg.configDir}/${name}" config.home.file
        && config.home.file."${cfg.configDir}/${name}".enable
      )
      [
        "config.nu"
        "env.nu"
        "login.nu"
      ];
in
{
  # Check the fully merged files, including Home Manager's generated imports.
  # Keep them as configuration files so Nushell controls startup evaluation.
  home.extraDependencies = lib.mkIf cfg.enable (
    map (
      name:
      myLib.writers.checkNuFile { inherit pkgs; } {
        name = "checked-nushell-${name}";
        src = config.home.file."${cfg.configDir}/${name}".source;
        nushell = if cfg.package == null then pkgs.nushell else cfg.package;
      }
    ) generatedFiles
  );
}
