{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # builder
    gnumake

    # debugger
    llvmPackages.lldb
    gdb

    # fix headers not found
    clang-tools

    # LSP and compiler
    llvmPackages.libstdcxxClang
    #gcc

    # other tools
    llvmPackages.libllvm
    valgrind
  ];
}
