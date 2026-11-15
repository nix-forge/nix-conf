{
  config,
  lib,
  self,
  pkgs,
  ...
}:
{
  # The aggregate includes developer fonts with limited grants. Keep it out of
  # the default installation until permission for the intended use is reviewed.
  fonts.packages = lib.optionals config.typography.restrictedFonts.enable [
    self.packages.${pkgs.stdenv.hostPlatform.system}.apple-fonts
  ];
}
