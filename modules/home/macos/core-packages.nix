{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  corePackageNames = [
    "acl"
    "attr"
    "bashInteractive"
    "bzip2"
    "coreutils-full"
    "cpio"
    "curl"
    "diffutils"
    "findutils"
    "gawk"
    "getent"
    "getconf"
    "gnugrep"
    "gnupatch"
    "gnused"
    "gnutar"
    "gzip"
    "xz"
    "less"
    "libcap"
    "ncurses"
    "netcat"
    "mkpasswd"
    "procps"
    "su"
    "time"
    "util-linux"
    "which"
    "zstd"
  ];

  resolvePackage =
    name:
    if !builtins.hasAttr name pkgs then
      [ ]
    else
      let
        pkg = pkgs.${name};
      in
      lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) pkg;

  corePackages =
    lib.concatMap resolvePackage corePackageNames
    ++ lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.stdenv.cc.libc) pkgs.stdenv.cc.libc;
in
{
  home.packages = lib.mkIf isDarwin corePackages;
}
