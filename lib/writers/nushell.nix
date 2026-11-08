{ lib, ... }: {
  checkNuFile =
    { pkgs }:
    {
      name,
      src,
      nushell ? pkgs.nushell,
    }:
    pkgs.runCommand name { } (
      (import ../templates/text.nix) ./scripts/check-nushell-source.sh {
        lib_escapeShellArg_src = lib.escapeShellArg "${src}";
        lib_getExe_nushell = lib.getExe nushell;
      }
    );
}
