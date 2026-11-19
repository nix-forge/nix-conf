{
  render =
    { pkgs, colors }:
    let
      rawPalette = pkgs.writeText "noctalia-stylix-palette-input.json" (
        builtins.toJSON ((import ./palette.nix).render { inherit colors; })
      );
    in
    pkgs.runCommand "noctalia-stylix-palette.json" { } ''
      ${
        pkgs.lib.getExe
          (import ../../../../../flake/runtime-packages.nix { pkgs = pkgs.buildPackages; }).preparePalette
      } ${rawPalette} "$out"
    '';
}
