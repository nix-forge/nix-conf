_: {
  reason = "FSEvents requires a host service denied by the Darwin sandbox.";
  upstream = "https://github.com/serokell/deploy-rs";
  removal = "The confirmation watcher test supports a hermetic backend.";
  reviewedRevision = "a591d4600e8ada8b22489093ebf50337f4d98065";
  inputPath = [ "deploy-rs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=tests::confirmation_watcher_observes_immediate_canary_removal"
      ];
    });
}
