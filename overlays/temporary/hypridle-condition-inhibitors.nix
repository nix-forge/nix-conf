{ pkgs, ... }: {
  reason = "Condition retries bypass active D-Bus inhibitors and can lock or suspend during video playback.";
  upstream = "https://github.com/hyprwm/hypridle/blob/v0.1.8/src/core/Hypridle.cpp";
  removal = "The pinned Hypridle rechecks inhibitors before retrying pending conditions and passes the retry regression.";
  reviewedRevision = "b1b875982b17dabde9b4a37f3e229e74913e6db3";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./patches/hypridle-condition-inhibitors.patch ];
      nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pkgs.python3 ];
      doCheck = true;
      postCheck = (old.postCheck or "") + ''
        python3 ${./tests/hypridle-condition-inhibitors.py} ../src/core/Hypridle.cpp
      '';
    });
}
