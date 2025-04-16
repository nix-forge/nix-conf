{
  self,
  config,
  inputs,
  pkgs,
  ...
}:
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

    # Set the language packs for firefox (be careful as unique configs lead to fingerprinting)s
    languagePacks = [
      "en-US"
    ];

    # Custom module for Global UserChrome
    userChrome.profiles."${config.home.username}.default" = {
      source = inputs.firefox-lepton-ui;
      recursive = true;
      # extraSettings = {
      #   "browser.uidensity" = 1;
      #   "ui.prefersReducedMotion" = 1;
      #   "browser.tabs.tabMinWidth" = 130;
      # };
    };

    profiles."${config.home.username}.default" = {
      id = 0;
      isDefault = true;
      name = "${config.home.username}.default";
    };
  };
}
