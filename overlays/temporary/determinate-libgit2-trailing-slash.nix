{ myLib, pkgs, ... }: {
  reason = "libgit2 cleanup on Linux and Darwin follows trailing-slash symlinks or rejects parent cleanup, and utility fixtures hard-code executables absent from the Nix sandbox.";
  upstream = "https://github.com/libgit2/libgit2";
  removal = "The selected libgit2 preserves symlink target files for one and multiple trailing slashes, and its complete upstream suites pass natively.";
  reviewedRevision = "f43bee4f45c2d42e7d1f4e37908ec5c7bb0fdba1";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    # Guard the fixed-output content, independent of store location or name.
    if
      package.version != "2.0.0-rc.1"
      || (package.src.outputHash or null) != "sha256-3sbqHm37SOwBeFgtjI2DLN6kx1F7G2N1m6rRIkqDXNI="
      || (package.src.outputHashMode or null) != "recursive"
    then
      throw "Review the selected libgit2 version and source content before applying its cleanup repair"

    else
      package.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + (myLib.templates.renderText
            {
              name = "prepare-libgit2-utility-tools.sh";
              text = ''
                # shellcheck shell=bash
                substituteInPlace tests/util/process/env.c \
                  --replace-fail /usr/bin/env @env@
                substituteInPlace tests/util/process/start.c \
                  --replace-fail '"/usr/bin/false"' '"@false@"' \
                  --replace-fail '"/bin/false"' '"@false@"' \
                  --replace-fail /bin/cat @cat@ \
                  --replace-fail /bin/pwd @pwd@
              '';
            }
            {
              env = pkgs.lib.getExe' pkgs.buildPackages.coreutils "env";
              false = pkgs.lib.getExe' pkgs.buildPackages.coreutils "false";
              cat = pkgs.lib.getExe' pkgs.buildPackages.coreutils "cat";
              pwd = pkgs.lib.getExe' pkgs.buildPackages.coreutils "pwd";
            }
          );
        patches = old.patches ++ [
          (builtins.path {
            path = ./patches/libgit2-trailing-slash.patch;
            name = "libgit2-trailing-slash.patch";
          })
        ];
        patchFlags = [
          "-p1"
          "--fuzz=0"
        ];
        checkPhase = old.checkPhase + (''
          # shellcheck shell=bash
          printf '%s\n' 'NIX_FORGE_LIBGIT2_FULL_UTIL_BEGIN util_tests -v -v'
          status=0
          ./util_tests -v -v || status=$?
          printf 'NIX_FORGE_LIBGIT2_FULL_UTIL_END status=%s\n' "$status"
          test "$status" -eq 0
        '');
      });
}
