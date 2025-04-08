{
  programs.firefox.policies.ExtensionSettings = {
    "*".installation_mode = "blocked"; # blocks all addons except the ones specified below

    # Query AMO Addon ID
    "queryamoid@kaply.com" = {
      "installation_mode" = "force_installed";
      "install_url" =
        "https://github.com/mkaply/queryamoid/releases/download/v0.2/query_amo_addon_id-0.2-fx.xpi";
    };

    # uBlock Origin
    "uBlock0@raymondhill.net" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      "private_browsing" = true;
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
      "install_url" =
        "https://addons.mozilla.org/firefox/downloads/latest/enhancer-for-youtube/latest.xpi";
    };

    # Refined GitHub
    "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = {
      "installation_mode" = "force_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/refined-github-/latest.xpi";
    };

    # Bitwarden
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
      "installation_mode" = "force_installed";
      "install_url" =
        "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
    };

    # Bypass Paywalls
    "bypasspaywalls@bypasspaywalls" = {
      "installation_mode" = "force_installed";
      "install_url" =
        "https://github.com/iamadamdev/bypass-paywalls-chrome/releases/latest/download/bypass-paywalls-firefox.xpi";
    };

    # Grammarly
    "87677a2c52b84ad3a151a4a72f5bd3c4@jetpack" = {
      "installation_mode" = "normal_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/grammarly-1/latest.xpi";
    };

    # Simplify Jobs Resume Helper
    "sabre@simplify.jobs" = {
      "installation_mode" = "normal_installed";
      "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/simplify-jobs/latest.xpi";
    };
  };
}
