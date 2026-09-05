{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  cfg = config.macos;

  lowerPriority = pkg: lib.setPrio ((pkg.meta.priority or lib.meta.defaultPriority) + 3) pkg;

  gnuPackages = with pkgs; [
    bashInteractive
    bzip2
    coreutils-full
    cpio
    curl
    diffutils
    findutils
    gawk
    getconf
    getent
    gnugrep
    gnupatch
    gnused
    gnutar
    gzip
    less
    mkpasswd
    ncurses
    netcat
    perl
    procps
    rsync
    time
    util-linux
    which
    xz
    zstd
  ];

  corePackages = map lowerPriority gnuPackages;

  commandLinks =
    name: priority: commands:
    lib.setPrio priority (
      pkgs.runCommandLocal name { } ''
        install -d "$out/bin"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            command: path: "ln -s ${lib.escapeShellArg path} \"$out/bin/${command}\""
          ) commands
        )}
      ''
    );

  commandWrappers =
    name: priority: commands:
    lib.setPrio priority (
      pkgs.runCommandLocal name { } ''
        install -d "$out/bin"
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (command: path: ''
            printf '%s\n' \
              '#!${lib.getExe pkgs.bash}' \
              'exec ${path} "$@"' \
              > "$out/bin/${command}"
            chmod 0755 "$out/bin/${command}"
          '') commands
        )}
      ''
    );

  nativeCommands = {
    awk = "/usr/bin/awk";
    basename = "/usr/bin/basename";
    bzip2 = "/usr/bin/bzip2";
    cat = "/bin/cat";
    chmod = "/bin/chmod";
    cp = "/bin/cp";
    cpio = "/usr/bin/cpio";
    curl = "/usr/bin/curl";
    date = "/bin/date";
    dd = "/bin/dd";
    df = "/bin/df";
    diff = "/usr/bin/diff";
    dirname = "/usr/bin/dirname";
    du = "/usr/bin/du";
    env = "/usr/bin/env";
    find = "/usr/bin/find";
    getconf = "/usr/bin/getconf";
    grep = "/usr/bin/grep";
    gzip = "/usr/bin/gzip";
    head = "/usr/bin/head";
    id = "/usr/bin/id";
    less = "/usr/bin/less";
    ln = "/bin/ln";
    ls = "/bin/ls";
    mkdir = "/bin/mkdir";
    mv = "/bin/mv";
    nc = "/usr/bin/nc";
    patch = "/usr/bin/patch";
    ps = "/bin/ps";
    pwd = "/bin/pwd";
    readlink = "/usr/bin/readlink";
    rm = "/bin/rm";
    rmdir = "/bin/rmdir";
    sed = "/usr/bin/sed";
    sort = "/usr/bin/sort";
    stat = "/usr/bin/stat";
    stty = "/bin/stty";
    tail = "/usr/bin/tail";
    tar = "/usr/bin/tar";
    tee = "/usr/bin/tee";
    time = "/usr/bin/time";
    top = "/usr/bin/top";
    touch = "/usr/bin/touch";
    tr = "/usr/bin/tr";
    uname = "/usr/bin/uname";
    uniq = "/usr/bin/uniq";
    wc = "/usr/bin/wc";
    which = "/usr/bin/which";
  };

  darwinCoupledCommands = lib.getAttrs [ "nc" "ps" "stty" "tar" "top" ] nativeCommands;

  nativeDarwinCommands =
    commands: commandLinks "macos-native-command-wrappers" (lib.meta.defaultPriority - 1) commands;

  # GNU coreutils dispatches on argv[0], so aliases such as `gls` need exec
  # wrappers rather than symlinks directly to the package binaries.
  explicitGnuCommands =
    commandWrappers "macos-explicit-gnu-command-wrappers" (lib.meta.defaultPriority - 2)
      {
        gcat = "${pkgs.coreutils-full}/bin/cat";
        gcp = "${pkgs.coreutils-full}/bin/cp";
        gdate = "${pkgs.coreutils-full}/bin/date";
        gdf = "${pkgs.coreutils-full}/bin/df";
        gdu = "${pkgs.coreutils-full}/bin/du";
        gfind = "${pkgs.findutils}/bin/find";
        ggrep = "${pkgs.gnugrep}/bin/grep";
        ghead = "${pkgs.coreutils-full}/bin/head";
        gls = "${pkgs.coreutils-full}/bin/ls";
        gmv = "${pkgs.coreutils-full}/bin/mv";
        gpatch = "${pkgs.gnupatch}/bin/patch";
        greadlink = "${pkgs.coreutils-full}/bin/readlink";
        grm = "${pkgs.coreutils-full}/bin/rm";
        gsed = "${pkgs.gnused}/bin/sed";
        gsort = "${pkgs.coreutils-full}/bin/sort";
        gstat = "${pkgs.coreutils-full}/bin/stat";
        gtail = "${pkgs.coreutils-full}/bin/tail";
        gtar = "${pkgs.gnutar}/bin/tar";
        gtr = "${pkgs.coreutils-full}/bin/tr";
        libressl-nc = "${pkgs.netcat}/bin/nc";
      };
in
{
  options.macos = {
    commandProfile = lib.mkOption {
      type = lib.types.enum [
        "native-first"
        "gnu-first"
      ];
      default = "native-first";
      description = ''
        Which command interface wins for names shared by macOS and GNU tools.
        The native-first profile also installs conventional g-prefixed GNU
        aliases for scripts that require GNU behavior.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional Darwin-only packages for the Home Manager profile.";
    };
  };

  config = lib.mkIf isDarwin {
    home.packages =
      corePackages
      ++ cfg.extraPackages
      ++ [ explicitGnuCommands ]
      ++ [
        (nativeDarwinCommands (
          if cfg.commandProfile == "native-first" then nativeCommands else darwinCoupledCommands
        ))
      ];
  };
}
