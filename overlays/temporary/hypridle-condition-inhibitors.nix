{ pkgs, ... }: {
  reason = "Condition retries bypass active D-Bus inhibitors and can lock or suspend during video playback.";
  upstream = "https://github.com/hyprwm/hypridle/blob/v0.1.8/src/core/Hypridle.cpp";
  removal = "The pinned Hypridle rechecks inhibitors before retrying pending conditions and passes the retry regression.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hypridle-condition-inhibitors.patch ];
      nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.python3 ];
      doCheck = true;
      postCheck =
        (old.postCheck or "")
        + ((import ../../lib/templates/text.nix) ./scripts/check-hypridle-condition-inhibitors.sh {
          tests_hypridle_condition_inhibitors_cc = ./tests/hypridle-condition-inhibitors.cc;
          tests_hypridle_condition_inhibitors_py = ./tests/hypridle_condition_inhibitors.py;
        });
    });
}
