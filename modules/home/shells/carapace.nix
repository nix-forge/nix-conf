{
  programs.carapace = {
    enable = true;
    ignoreCase = true;
  };

  # Only bridge to installed shells. Nushell uses Carapace's native support.
  home.sessionVariables.CARAPACE_BRIDGES = "zsh,bash";
}
