{ config, lib, ... }: {
  programs.eza = {
    enable = true;

    colors = "auto";
    # Checking Git status on every directory listing is noticeable in large
    # repositories. Keep it available through `lg` instead.
    git = false;
    icons = "auto";
    extraOptions = [
      "--group-directories-first"
      "--hyperlink"
      "auto"
    ];
    # Home Manager defaults this integration to false, unlike its other
    # shell integrations. Keep it consistent with the shared policy.
    enableNushellIntegration = config.programs.nushell.enable;
  };

  home.shellAliases = {
    ls = lib.mkDefault "eza --icons auto --color auto --group-directories-first";
    l = "eza --all --icons auto --color auto --hyperlink auto --group-directories-first";
    la = "eza --all --icons auto --color auto --hyperlink auto --group-directories-first";
    ll = "eza --long --all --icons auto --color auto --hyperlink auto --group-directories-first";
    lla = "eza --long --all --icons auto --color auto --hyperlink auto --group-directories-first";
    lt = "eza --tree --long --level=2 --icons auto --color auto --hyperlink auto";
    lg = "eza --long --all --git --git-repos --icons auto --color auto --hyperlink auto";
  };
}
