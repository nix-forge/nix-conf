{ pkgs, ... }: {
  reason = "Condition retries bypass active D-Bus inhibitors and can lock or suspend during video playback.";
  upstream = "https://github.com/hyprwm/hypridle/blob/v0.1.8/src/core/Hypridle.cpp";
  removal = "The pinned Hypridle rechecks inhibitors before retrying pending conditions and passes the retry regression.";
  reviewedRevision = "4975466d324710c576dc11ad614684e6bd8cad8e";
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
