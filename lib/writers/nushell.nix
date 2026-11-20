{ lib, ... }: {
  checkNuFile =
    { pkgs }:
    {
      name,
      src,
      nushell ? pkgs.nushell,
    }:
    pkgs.runCommand name { } (
      ((import ./bash.nix { inherit (pkgs) lib; }).renderBashText { inherit pkgs; })
        {
          name = "check-nushell-source.sh";
          text = ''
            # shellcheck shell=bash
            # Nix builder/activation callers and rendered fragments provide external variables. Quoted fragments retain literal dollars.
            # shellcheck disable=SC2016,SC2154
            export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
            mkdir -p "$HOME" "$XDG_CONFIG_HOME"
            NU_CHECK_FILE=@lib_escapeShellArg_src@ @lib_getExe_nushell@ --no-config-file --commands \
              'if not (nu-check --debug $env.NU_CHECK_FILE) { exit 1 }'
            cp @lib_escapeShellArg_src@ "$out"
            chmod 0444 "$out"
          '';
        }
        {
          lib_escapeShellArg_src = lib.escapeShellArg "${src}";
          lib_getExe_nushell = lib.getExe nushell;
        }
    );
}
