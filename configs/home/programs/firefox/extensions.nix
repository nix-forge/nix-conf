profileName:
{ inputs, system, ... }:
let
  pkgsNur =
    (import inputs.nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
      overlays = [ inputs.nur.overlays.default ];
    }).nur;
in
{
  programs.firefox = {
    # Base extensions for all profiles
    policies.ExtensionSettings = {
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

      # SponsorBlock for YouTube
      "sponsorBlocker@ajay.app" = {
        "installation_mode" = "force_installed";
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
      };

      # TODO: Move more opinionated extensions to profile based installation
      # Simplify Jobs Resume Helper
      "sabre@simplify.jobs" = {
        "installation_mode" = "normal_installed";
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/simplify-jobs/latest.xpi";
      };
    };

    profiles.${profileName}.extensions = {
      packages = with pkgsNur.repos.rycee.firefox-addons; [
        bitwarden
        refined-github
        grammarly
      ];
    };
  };
}
