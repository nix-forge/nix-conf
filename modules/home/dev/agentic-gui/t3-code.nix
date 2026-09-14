{
  self,
  system,
  lib,
  ...
}:
{
  home.packages = lib.mkIf (self.packages.${system} ? t3-code) [ self.packages.${system}.t3-code ];
}
