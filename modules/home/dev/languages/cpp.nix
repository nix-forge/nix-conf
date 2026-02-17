{ pkgs, ... }:
{
  home.packages = with pkgs; [
    clang
    clang-tools
    lld
    lldb

    codeql
    cppcheck
    # gdb
    cmake
    ninja
    meson
    pkg-config
    bear
  ];
}
