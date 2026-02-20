{
  programs.firefox = {
    # profiles.default.extensions.force = true;

    # Base extensions for all profiles
    policies.ExtensionSettings = {
      # Query AMO Addon ID
      "queryamoid@kaply.com" = {
        "installation_mode" = "force_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" =
          "https://github.com/mkaply/queryamoid/releases/download/v0.2/query_amo_addon_id-0.2-fx.xpi";
        "default_area" = "menupanel";
      };

      # uBlock Origin
      "uBlock0@raymondhill.net" = {
        "installation_mode" = "force_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        "private_browsing" = true;
        "default_area" = "navbar";
      };

      # SponsorBlock for YouTube
      "sponsorBlocker@ajay.app" = {
        "installation_mode" = "force_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
        "default_area" = "menupanel";
      };

      # Bitwarden Password Manager
      "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
        "installation_mode" = "force_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" =
          "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
        "default_area" = "navbar";
      };

      # Refined GitHub
      "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = {
        "installation_mode" = "normal_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/refined-github-/latest.xpi";
        "default_area" = "menupanel";
      };

      # Adaptive Tab Bar Color
      "ATBC@EasonWong" = {
        "installation_mode" = "normal_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" =
          "https://addons.mozilla.org/firefox/downloads/latest/adaptive-tab-bar-colour/latest.xpi";
        "default_area" = "menupanel";
      };

      # Simplify Jobs Resume Helper
      "sabre@simplify.jobs" = {
        "installation_mode" = "normal_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/simplify-jobs/latest.xpi";
        "default_area" = "menupanel";
      };
    };
  };
}
