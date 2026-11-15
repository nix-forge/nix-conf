{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  cfg = config.programs.jujutsu.runtimeIdentity;
  destination = "${config.xdg.configHome}/jj/conf.d/90-local-identity.toml";
  gitPackage = if config.programs.git.package == null then pkgs.git else config.programs.git.package;
  writer = pkgs.writers.writePython3Bin "write-jujutsu-identity" {
    libraries = [ (myLib.python.notificationProcess { inherit pkgs; }) ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } ./scripts/write_jujutsu_identity.py;
  arguments =
    if cfg.sourceFile != null then
      [
        "--source"
        cfg.sourceFile
        destination
      ]
    else
      [
        "--git"
        (lib.getExe' gitPackage "git")
        destination
      ];
in
{
  key = "nix-conf/jj-identity/homeManager";
  options.programs.jujutsu.runtimeIdentity = {
    enable = lib.mkEnableOption "private Jujutsu identity loaded at activation";
    sourceFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/credentials/jujutsu-identity.toml";
      description = "Protected runtime TOML file containing only user.name and user.email. Null derives the identity from Git's global configuration.";
    };
    activationAfter = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional Home Manager activation entries that provide the runtime identity file.";
    };
  };
  config = lib.mkIf cfg.enable {
    programs.jujutsu.enable = lib.mkDefault true;
    assertions = [
      {
        assertion =
          cfg.sourceFile == null
          || (
            lib.hasPrefix "/" cfg.sourceFile
            && !lib.hasPrefix "/nix/store" cfg.sourceFile
            && !lib.elem ".." (lib.splitString "/" cfg.sourceFile)
          );
        message = "Jujutsu runtime identity sourceFile must be an absolute runtime path outside the Nix store.";
      }
      {
        assertion = config.programs.jujutsu.enable;
        message = "Jujutsu runtime identity requires programs.jujutsu.enable.";
      }
      {
        assertion = cfg.sourceFile != null || config.programs.git.enable;
        message = "Jujutsu runtime identity without sourceFile requires programs.git.enable.";
      }
    ];
    home.activation.jujutsuLocalIdentity = lib.hm.dag.entryAfter (
      [ "writeBoundary" ] ++ cfg.activationAfter
    ) "run ${lib.getExe writer} ${lib.escapeShellArgs arguments}";
  };
}
