{
  self,
  system,
  lib,
  ...
}:
{
  home.packages = lib.mkIf (builtins.hasAttr "openai-codex-desktop" self.packages.${system}) [
    self.packages.${system}.openai-codex-desktop
  ];
}
