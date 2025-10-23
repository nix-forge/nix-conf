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

    bashInteractive
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
    inetutils
    net-tools
    iproute2mac
    lsof
    pkg-config
    gettext
    libiconv
    rsync
    man-db
    texinfo
    tmux
    fzf
    ripgrep
    fd
    bat
  ];
}
