{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  lowerPriority = pkg: lib.setPrio ((pkg.meta.priority or lib.meta.defaultPriority) + 3) pkg;

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
      lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) (lowerPriority pkg);

  corePackages =
    lib.concatMap resolvePackage corePackageNames
    ++ lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.stdenv.cc.libc) pkgs.stdenv.cc.libc;

  nativeCommand =
    name: path:
    pkgs.replaceVarsWith {
      inherit name;
      src = ./native-command.sh;
      dir = "bin";
      isExecutable = true;
      replacements = {
        bash = lib.getExe pkgs.bash;
        command = path;
      };
    };

  # Keep the GNU userland as the normal PATH default, but preserve macOS tools
  # whose interface is coupled to Darwin kernel APIs or filesystem metadata.
  # The priority is intentionally higher than the lowered GNU package priority
  # above, so these wrappers win in the Home Manager profile without PATH hacks.
  nativeDarwinCommands = lib.setPrio (lib.meta.defaultPriority - 1) (
    pkgs.symlinkJoin {
      name = "macos-native-command-wrappers";
      paths = [
        (nativeCommand "stty" "/bin/stty")
        (nativeCommand "nc" "/usr/bin/nc")
        (nativeCommand "ps" "/bin/ps")
        (nativeCommand "top" "/usr/bin/top")
        (nativeCommand "tar" "/usr/bin/tar")
        (nativeCommand "gtar" "${pkgs.gnutar}/bin/tar")
        (nativeCommand "libressl-nc" "${pkgs.netcat}/bin/nc")
      ];
    }
  );
in
{
  home.packages = lib.mkIf isDarwin (corePackages ++ [ nativeDarwinCommands ]);
}
