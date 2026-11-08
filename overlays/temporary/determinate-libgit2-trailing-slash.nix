{ pkgs, ... }: {
  reason = "libgit2 cleanup on Linux and Darwin follows trailing-slash symlinks or rejects parent cleanup, and utility fixtures hard-code executables absent from the Nix sandbox.";
  upstream = "https://github.com/libgit2/libgit2";
  removal = "The selected libgit2 preserves symlink target files for one and multiple trailing slashes, and its complete upstream suites pass natively.";
  reviewedRevision = "9993a12bd434f653d5081b9b35f50900412fece8";
  inputPath = [
    "determinate"
    "inputs"
    "nix"
  ];
  apply =
    package:
    assert toString package.src == "/nix/store/mf7h0dk8cdgy6ckaknzkc6hfqw96z8rp-source";
    assert package.doCheck;
    package.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ((import ../../lib/templates/text.nix) ./scripts/prepare-libgit2-utility-tools.sh {
          env = pkgs.lib.getExe' pkgs.buildPackages.coreutils "env";
          false = pkgs.lib.getExe' pkgs.buildPackages.coreutils "false";
          cat = pkgs.lib.getExe' pkgs.buildPackages.coreutils "cat";
          pwd = pkgs.lib.getExe' pkgs.buildPackages.coreutils "pwd";
        });
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
      checkPhase = old.checkPhase + builtins.readFile ./scripts/check-libgit2-full-util.sh;
    });
}
