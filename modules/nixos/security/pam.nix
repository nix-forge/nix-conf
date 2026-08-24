{ lib, ... }: {
  security.pam.services.su.requireWheel = lib.mkDefault true;

  # Authentication methods, keyring unlocks, resource limits, lock screens,
  # and account-lockout thresholds are role- and host-specific. Keep them in
  # local/ so this shared baseline does not unexpectedly alter a server,
  # recovery image, smart-card workflow, or another desktop environment.
  #
  # In particular, do not enable pam_gnupg or pam_faillock here: the former
  # requires an intentionally managed private-key/keygrip setup, while the
  # latter requires ordered pre-auth, failure, and success rules that should
  # be designed and tested for each authentication surface.
}
