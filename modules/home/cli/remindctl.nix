{
  self,
  system,
  lib,
  ...
}:
{
  home.packages = lib.mkIf (self.packages.${system} ? remindctl) [
    self.packages.${system}.remindctl
  ];
}
