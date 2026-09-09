{ lib, ... }: {
  checkNuFile =
    { pkgs }:
    {
      name,
      src,
      nushell ? pkgs.nushell,
    }:
    pkgs.runCommand name { } ''
      export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config"
      mkdir -p "$HOME" "$XDG_CONFIG_HOME"
      NU_CHECK_FILE=${lib.escapeShellArg "${src}"} ${lib.getExe nushell} --no-config-file --commands \
        'if not (nu-check --debug $env.NU_CHECK_FILE) { exit 1 }'
      cp ${lib.escapeShellArg "${src}"} "$out"
      chmod 0444 "$out"
    '';
}
