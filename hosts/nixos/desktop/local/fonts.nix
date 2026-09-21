{ self, pkgs, ... }: {
  # The consolidated package owns the Apple catalog and developer-font
  # distributions. Install it once through the system font directory.
  fonts.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.apple-fonts ];
}
