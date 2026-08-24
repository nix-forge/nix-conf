{
  # Enable the kernel MAC framework and its declarative NixOS policy loader.
  # The current desktop intentionally has no hand-written host policy yet:
  # generic upstream profiles are not automatically loaded, and blanket GUI
  # confinement would be unreliable with the Hyprland/NVIDIA/remote-play
  # desktop stack.  Docker supplies its own enforced `docker-default` profile
  # for non-privileged containers once AppArmor is active.
  security.appArmorBaseline.enable = true;

  security.apparmor = {
    # Avoid stale, store-path-specific compiled cache entries.  Parsing the
    # small explicit profile set at boot/reload is a better desktop trade-off.
    enableCache = false;

    # Never surprise an interactive session by terminating processes merely
    # because a future rebuild adds a profile.  Deploy the profile, then
    # restart only its owning service or application at a planned time.
    killUnconfinedConfinables = false;

    # Add system-specific policies here, each as a Nix expression with either
    # `profile` or `path` (never both).  Keep application-specific paths,
    # data directories, device access, network allowances, and complain vs.
    # enforce decisions in this host-local file.  Do not add a permissive
    # catch-all profile: it would create noise without meaningful isolation.
    policies = { };
  };
}
