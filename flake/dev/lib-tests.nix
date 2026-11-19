{ inputs, ... }: {
  flake.libTests = import ../../lib/tests { inherit (inputs.nixpkgs) lib; };
  perSystem = { pkgs, ... }: {
    checks.lib-tests = pkgs.runCommand "lib-tests" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      nix-unit --eval-store "$TMPDIR/eval-store" \
        --expr 'import ${../../lib}/tests { lib = import ${pkgs.path}/lib; }'
      touch "$out"
    '';
  };
}
