{ pkgs, ... }:
{
  home.packages = with pkgs; [
    clang
    clang-tools
    lld
    lldb

    codeql
    clang-tools
    cppcheck
    # gdb
    cmake
    ninja
    meson
    pkg-config
    bear
  ];
}
