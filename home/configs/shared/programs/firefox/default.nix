{
  self,
  config,
  inputs,
  ...
}:
let
  profile = "${config.home.username}.default";
  profileName = "${config.home.username}-default";
in
{
  programs.firefox.enable = true;

  imports = [
    ./blocking.nix
    ./policies.nix
    ./extensions.nix
    ./user-js.nix
    self.homeModules.firefox-userchrome
  ];

  programs.firefox.userChrome.profiles.${profile} = {
    source = inputs.firefox-lepton-ui;
    recursive = true;
    # extraSettings = { # settings specific to my theme
    #   "browser.uidensity" = 1;
    #   "ui.prefersReducedMotion" = 1;
    #   "browser.tabs.tabMinWidth" = 130;
    # };
  };

  programs.firefox.profiles.${profile} = {
    id = 0;
    isDefault = true;
    name = profileName;

    settings = {
      "devtools.chrome.enabled" = true;
      "devtools.debugger.remote-enabled" = true;
      "signon.rememberSignons" = false;
      # "Open previous windows and tabs"
      "browser.startup.page" = 3;
      "trailhead.firstrun.didSeeAboutWelcome" = true;
    };
  };
}
