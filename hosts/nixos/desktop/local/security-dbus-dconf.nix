{ pkgs, ... }: {
  security.dbusDconfBaseline.enable = true;

  # Preserve the conventional per-user writable database. This owner-managed
  # workstation has no centrally mandated GSettings values or locks: desktop
  # preferences belong in Home Manager or the user's dconf database, not in a
  # system-wide policy that could unexpectedly override the session.
  programs.dconf.profiles.user.enableUserDb = true;

  # dconf itself is installed by programs.dconf. Keep the optional graphical
  # inspector host-local: it is useful for diagnosing a particular desktop,
  # but it is neither a system service nor a universal baseline dependency.
  environment.systemPackages = [ pkgs.dconf-editor ];
}
