{ lib, ... }: {
  security.polkit = {
    # This is an owner-administered workstation.  Wheel is the sole Polkit
    # administrator identity, matching the sudo policy; do not add the root
    # account or an ordinary desktop user as an alternative prompt identity.
    adminIdentities = [ "unix-group:wheel" ];

    # The workstation's GUI uses D-Bus Polkit actions, not a general setuid
    # root command launcher.  Keep `pkexec` absent unless a specific reviewed
    # application requires it.
    enablePkexecWrapper = lib.mkForce false;

    # Keep the upstream five-minute authorization cache for a short sequence
    # of storage or firmware operations.  This is deliberately finite and is
    # scoped by Polkit to the action and subject, not a session-wide sudo grant.
    settings.Polkitd.ExpirationSeconds = 300;
    extraArgs = [
      "--no-debug"
      "--log-level=notice"
    ];
  };

}
