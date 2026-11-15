{
  render =
    { pkgs, colors }:
    let
      rawPalette = pkgs.writeText "noctalia-stylix-palette-input.json" (
        builtins.toJSON ((import ./palette.nix).render { inherit colors; })
      );
    in
    pkgs.runCommand "noctalia-stylix-palette.json" { } ''
      ${pkgs.python3}/bin/python ${./prepare_palette.py} ${rawPalette} "$out"
    '';
}
