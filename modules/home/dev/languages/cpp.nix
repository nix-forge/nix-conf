{ lib, pkgs, ... }: {
  home.packages =
    with pkgs;
    [
      clang
      # Clang wrappers already use priority 10; GNU aliases must rank below them.
      (lib.setPrio 20 pkgs.gcc)
      clang-tools
      lld
      lldb

      cppcheck
      gdb
      gnumake
      perl
      cmake
      ninja
      meson
      pkg-config
      bear
    ]
    ++ lib.optionals (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.codeql) [ pkgs.codeql ];
}
