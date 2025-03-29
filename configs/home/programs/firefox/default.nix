{
  self,
  config,
  inputs,
  pkgs,
  ...
}:
let
  profile = "${config.home.username}.default";
  profileName = "${config.home.username}-default";
in
{
  imports = [
    ./blocking.nix
    ./policies.nix
    ./extensions.nix
    ./user-js.nix
    self.homeManagerModules.firefox-userchrome
  ];

  programs.firefox = {
    enable = true;
    package = pkgs.firefox;

    # Set the language packs for firefox (be careful as unique configs lead to fingerprinting)s
    languagePacks = [
      "en-US"
    ];

    # Custom module for Global UserChrome
    userChrome.profiles.${profile} = {
      source = inputs.firefox-lepton-ui;
      recursive = true;
      # extraSettings = { # settings specific to my theme
      #   "browser.uidensity" = 1;
      #   "ui.prefersReducedMotion" = 1;
      #   "browser.tabs.tabMinWidth" = 130;
      # };
    };

    profiles.${profile} = {
      id = 0;
      isDefault = true;
      name = profileName;
    };
  };

  # install companion app for Firefox Extension "Video DownloadHelper"
  home.packages = [ pkgs.vdhcoapp ];
}
