_: {
  reason = "Darwin filesystem events use canonical paths, but confirmation compares a lexical canary path.";
  upstream = "https://github.com/serokell/deploy-rs/blob/1cec0527bd09074bbee6d4461900ce5d58267217/src/bin/activate.rs";
  removal = "The unmodified confirmation helper passes the real directory-alias removal regression on Darwin.";
  reviewedRevision = "1cec0527bd09074bbee6d4461900ce5d58267217";
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
