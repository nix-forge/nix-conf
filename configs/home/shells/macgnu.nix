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
    indent
    gnused
    gnutar
    which
    gnugrep
    gzip
    screen

    bash
    emacs
    gnupatch
    less
    gnum4
    gnumake
    nano
    bison

    flex
    file
    procps
    tree
    wget
    curl
    watch
    wdiff
    autoconf
  ];
}
