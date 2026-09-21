_: {
  reason = "FSEvents requires a host service denied by the Darwin sandbox.";
  upstream = "https://github.com/serokell/deploy-rs";
  removal = "The confirmation and cancellation watcher tests support a hermetic backend.";
  reviewedRevision = "e760371d631165e7d8de5b0dcf148e21ec4c16f0";
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
