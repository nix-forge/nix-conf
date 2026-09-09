_: {
  reason = "FSEvents requires a host service denied by the Darwin sandbox.";
  upstream = "https://github.com/serokell/deploy-rs";
  removal = "The confirmation and cancellation watcher tests support a hermetic backend.";
  reviewedRevision = "110c8f134ac8c4a7ef73aa10d972185b3ca54e4e";
  inputPath = [ "deploy-rs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=tests::confirmation_watcher_observes_immediate_canary_removal"
        # These cases also wait for FSEvents from the denied host service.
        # Keep the existing-sentinel and sentinel-removal tests enabled.
        "--skip=tests::wait_cancelled_when_cancel_file_created_while_waiting"
        "--skip=tests::wait_returns_when_canary_created_while_waiting"
      ];
    });
}
