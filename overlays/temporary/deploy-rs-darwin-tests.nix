_: {
  reason = "FSEvents streams fail to start in the strict Darwin build sandbox.";
  upstream = "https://github.com/serokell/deploy-rs";
  removal = "The confirmation and cancellation watcher tests support a hermetic backend.";
  reviewedRevision = "1cec0527bd09074bbee6d4461900ce5d58267217";
  inputPath = [ "deploy-rs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=tests::confirmation_watcher_observes_immediate_canary_removal"
        # These cases also wait for FSEvents that cannot start in the build sandbox.
        # Keep the existing-sentinel and sentinel-removal tests enabled.
        "--skip=tests::wait_cancelled_when_cancel_file_created_while_waiting"
        "--skip=tests::wait_returns_when_canary_created_while_waiting"
      ];
    });
}
