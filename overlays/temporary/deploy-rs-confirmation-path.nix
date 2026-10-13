# Register only after the native normal-directory and alias controls pass.
_: {
  reason = "Darwin filesystem events use canonical paths, but confirmation compares a lexical canary path.";
  upstream = "https://github.com/serokell/deploy-rs/blob/45ba3f8c5cb28396fff71671806e2550b464ac86/src/bin/activate.rs";
  removal = "The unmodified confirmation helper passes the real directory-alias removal regression on Darwin.";
  reviewedRevision = "45ba3f8c5cb28396fff71671806e2550b464ac86";
  inputPath = [ "deploy-rs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (builtins.path {
          path = ./patches/deploy-confirmation-parent-path.patch;
          name = "deploy-confirmation-parent-path.patch";
        })
      ];
    });
}
