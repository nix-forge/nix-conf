{ self, pkgs, ... }: {
  # The desktop's general font collection belongs to Home Manager. Install
  # these extra document families once, through the system font directory.
  fonts.packages =
    (import ../../../../modules/shared/font-packages.nix { }).appleDocumentFonts
      self.packages.${pkgs.stdenv.hostPlatform.system};
}
