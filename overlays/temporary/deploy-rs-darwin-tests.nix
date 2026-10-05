_: {
  reason = "FSEvents requires a host service denied by the Darwin sandbox.";
  upstream = "https://github.com/serokell/deploy-rs";
  removal = "The confirmation and cancellation watcher tests support a hermetic backend.";
  reviewedRevision = "cf64c8cbadd9b13ea79ba7720aa2930500f2ece7";
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
