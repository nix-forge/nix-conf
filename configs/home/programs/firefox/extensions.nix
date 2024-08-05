{
  programs.firefox.policies.ExtensionSettings = {
    # Query AMO Addon ID
    "queryamoid@kaply.com" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://github.com/mkaply/queryamoid/releases/download/v0.2/query_amo_addon_id-0.2-fx.xpi";
    };

    # uBlock Origin
    "uBlock0@raymondhill.net" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
    };

    # Skip Redirect
    "skipredirect@sblask" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/skip-redirect/latest.xpi";
    };

    # Dark Reader
    "addon@darkreader.org" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
    };

    # SponsorBlock for YouTube
    "sponsorBlocker@ajay.app" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
    };

    # Enhancer for YouTube
    "enhancerforyoutube@maximerf.addons.mozilla.org" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/enhancer-for-youtube/latest.xpi";
    };

    # Refined GitHub
    "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/refined-github-/latest.xpi";
    };

    # Bitwarden
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
    };

    # Bypass Paywalls
    "bypasspaywalls@bypasspaywalls" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://github.com/iamadamdev/bypass-paywalls-chrome/releases/latest/download/bypass-paywalls-firefox.xpi";
    };
  };
}
