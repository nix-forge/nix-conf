{ pkgs, lib, ... }:
{
  home.packages = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
    with pkgs;
    [
      coreutils # TODO: consider using uutil-coreutils once more stable
      darwin.binutils
      diffutils # TODO: consider using uutil-diffutils once more stable
      findutils # TODO: consider using uutil-findutils once more stable
      util-linux

      ed
      gawk
      gnused
      gnutar
      which
      gnugrep
      gzip
      gnupatch
      less
      gnumake

      procps
      file
      libiconv
      curl
      wget
      tree
    ]
  );
}
