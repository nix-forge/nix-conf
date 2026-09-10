{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  inherit ((import ../../modules/shared/stylix/schemes.nix { inherit inputs; })) schemes;
  base16 = inputs.stylix.inputs.base16.lib { inherit pkgs lib; };
  target = ../../modules/shared/stylix/targets/noctalia;
  fixtures = lib.mapAttrs (
    _: scheme:
    let
      colors = (base16.mkSchemeAttrs scheme).withHashtag;
    in
    {
      original = (import (target + /palette.nix)).render { inherit colors; };
      prepared = (import (target + /mk-palette.nix)).render { inherit pkgs colors; };
    }
  ) schemes;
  manifest = pkgs.writeText "noctalia-palette-fixtures.json" (builtins.toJSON fixtures);
in
pkgs.runCommand "noctalia-palette-contrast" { } ''
  ${pkgs.python3}/bin/python ${./check-noctalia-palettes.py} ${manifest} > "$out"
''
