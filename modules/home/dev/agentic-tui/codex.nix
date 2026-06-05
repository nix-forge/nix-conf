{
  lib,
  pkgs,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isAarch64;
  supportsRemindctl = isDarwin && isAarch64;
  remindctl = self.packages.${system}.remindctl;
in
{
  home.packages = lib.optional supportsRemindctl remindctl;

  programs.codex = {
    enable = true;
    package = pkgs.codex;
    skills = lib.optionalAttrs supportsRemindctl { apple-reminders = remindctl.agentSkill; };
  };
}
