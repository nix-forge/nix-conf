{ lib, ... }: {
  # This interactive host must not advertise fourteen concurrent derivations
  # each with an unbounded compiler pool. Native job receipts separately state
  # that daemon builders are outside the macOS process-group watchdog.
  nix.settings = {
    max-jobs = lib.mkForce 1;
    cores = lib.mkForce 8;
    eval-cores = lib.mkForce 4;
  };
}
