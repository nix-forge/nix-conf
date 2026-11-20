{ pkgs, ... }: {
  home.packages = [
    pkgs.lsof
    # psmisc supplies Linux pstree and fuser; Darwin uses the portable pstree.
    (if pkgs.stdenv.hostPlatform.isLinux then pkgs.psmisc else pkgs.pstree)
  ];
}
