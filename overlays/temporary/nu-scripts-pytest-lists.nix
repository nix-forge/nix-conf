{ lib, pkgs, ... }: {
  reason = "nu_scripts pytest completions use semicolons that omit choices on Nushell 0.115.1 and fail parsing on 0.116.1.";
  upstream = "https://github.com/nushell/nu_scripts/pull/1287";
  removal = "The selected upstream pytest completion parses, offers both log-file-mode and assert choices, and the full generated Nushell configuration passes without this patch.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  affectedVersions = {
    from = "0-unstable-2026-10-02";
    until = "0-unstable-2026-10-03";
  };
  apply =
    package:
    assert lib.assertMsg (
      (package.src.hash or package.src.outputHash or null)
      == "sha256-/6nbTNfpkNRUJcXnQKw9yrm3UAvgfUoyKbNRUkQAfPY="
    ) "Temporary upstream fix 'nu-scripts-pytest-lists' needs review: completion source changed.";
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (builtins.path {
          path = ./patches/nu-scripts-pytest-lists.patch;
          name = "nu-scripts-pytest-lists.patch";
        })
      ];
      patchFlags = (old.patchFlags or [ "-p1" ]) ++ [ "--fuzz=0" ];
      doInstallCheck = true;
      postInstallCheck =
        (old.postInstallCheck or "")
        + ((import ../../lib/templates/text.nix) ./scripts/check-nu-scripts-pytest.sh {
          nu = lib.getExe pkgs.nushell;
        });
    });
}
