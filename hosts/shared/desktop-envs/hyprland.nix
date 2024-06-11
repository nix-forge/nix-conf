{ pkgs, inputs, ... }:
{
  # imports = [ inputs.hyprland.nixosModules.default ];
  programs.hyprland.enable = true;

  # hardware.opengl =
  #   let
  #     pkgs-unstable = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  #   in
  #   {
  #     package = pkgs-unstable.mesa.drivers;

  #     # if you also want 32-bit support (e.g for Steam)
  #     driSupport32Bit = true;
  #     package32 = pkgs-unstable.pkgsi686Linux.mesa.drivers;
  #   };
}
