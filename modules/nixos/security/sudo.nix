{ lib, ... }: {
  security.sudo = {
    enable = lib.mkDefault true;

    # Require a password for administrative elevation.  Do not add generic
    # NOPASSWD rules: tools such as systemctl, nixos-rebuild, and storage
    # utilities accept powerful arguments and are root-equivalent in practice.
    wheelNeedsPassword = lib.mkDefault true;

    # A command matched by `ALL` implicitly receives SETENV in sudoers unless
    # it is tagged NOSETENV.  Keep the normal environment sanitization intact
    # and do not preserve caller-controlled PATH, DISPLAY, or EDITOR values.
    defaultOptions = lib.mkDefault [ "NOSETENV" ];

    # Keep the daemon's secure operational defaults explicit and portable.
    # The five-minute cache is bounded per TTY, so a second terminal or a
    # remote session cannot reuse an administrator authentication silently.
    extraConfig = lib.mkAfter ''
      Defaults use_pty
      Defaults timestamp_type=tty
      Defaults timestamp_timeout=5
      Defaults passwd_tries=3
      Defaults !pwfeedback
      Defaults log_allowed
      Defaults log_denied
    '';
  };

  # Do not enable sudo input/output logging here: terminal recordings can
  # capture passwords, tokens, and private data, while imposing storage and
  # performance costs.  Normal sudo event logs remain enabled.  Any command
  # exception, logging backend, or different cache lifetime is a host-local
  # policy decision that must be tested with its exact command arguments.
}
