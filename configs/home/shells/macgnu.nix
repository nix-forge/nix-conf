{ pkgs, ... }:
{
  home.packages = with pkgs; [
    coreutils
    binutils
    diffutils
    findutils
    moreutils
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
  ];
}
