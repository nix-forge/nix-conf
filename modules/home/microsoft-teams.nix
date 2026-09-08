{
  self,
  system,
  lib,
  ...
}:
{
  home.packages = lib.mkIf (self.packages.${system} ? microsoft-teams) [
    self.packages.${system}.microsoft-teams
  ];
}
