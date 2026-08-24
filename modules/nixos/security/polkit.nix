{ config, lib, ... }: {
  security.polkit = {
    enable = lib.mkDefault true;

    # `pkexec` is a setuid root command launcher.  Desktop applications can
    # use Polkit's D-Bus authorization path without exposing this additional
    # general-purpose elevation interface.  Do not let a desktop environment
    # silently re-enable it; import a separate, reviewed profile if a host
    # genuinely needs this interface.
    enablePkexecWrapper = lib.mkForce false;

    # Keep administrator authentication aligned with NixOS administration:
    # wheel users can authorize admin actions, while ordinary users cannot
    # select root or an unrelated account in the graphical prompt.
    adminIdentities = lib.mkDefault [ "unix-group:wheel" ];

    # Five minutes is Polkit's upstream default.  It keeps a short sequence of
    # related desktop operations usable without turning an authorization into a
    # session-long grant.  Hosts may tune this UX/security trade-off locally.
    settings.Polkitd.ExpirationSeconds = lib.mkDefault 300;

    # Production logging must not capture every authorization request: action
    # metadata can include commands and user/session information.  The daemon
    # itself still records normal operational messages at notice level.  For a
    # temporary investigation, override these arguments locally and remove the
    # change again after collecting the required evidence.
    extraArgs = lib.mkDefault [
      "--no-debug"
      "--log-level=notice"
    ];
  };

  assertions = [
    {
      assertion = config.security.polkit.enable;
      message = "This interactive-system security baseline requires Polkit; use a dedicated minimal or appliance profile instead of disabling it here.";
    }
  ];

  # Do not add catch-all `polkit.Result.YES`, `AUTH_SELF`, or `*_KEEP` rules in
  # this shared baseline.  Rules are ordered JavaScript evaluated by polkitd,
  # so an overly broad rule can silently bypass a package's intended action
  # policy.  A graphical authentication agent and any exceptional action rules
  # are desktop- and service-specific and therefore belong in host local/.
}
