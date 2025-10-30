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
        "temporarily_allow_weak_signatures" = false;
        "install_url" =
          "https://github.com/mkaply/queryamoid/releases/download/v0.2/query_amo_addon_id-0.2-fx.xpi";
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
      };

      # TODO: Move more opinionated extensions to profile based installation (this will require creating a nix package based firefox extension most likely)
      # NOTE: It would be nice to have an automated way to create firefox packages instead of manually creating them for profiles
      # Simplify Jobs Resume Helper
      "sabre@simplify.jobs" = {
        "installation_mode" = "normal_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/simplify-jobs/latest.xpi";
      };

      "webextension@metamask.io" = {
        "installation_mode" = "normal_installed";
        "temporarily_allow_weak_signatures" = false;
        "install_url" = "https://addons.mozilla.org/firefox/downloads/latest/ether-metamask/latest.xpi";
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
