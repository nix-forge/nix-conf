{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (pkgs.nur.repos.rycee) firefox-addons;
in
{
  home.file.".mozilla/managed-storage/uBlock0@raymondhill.net.json".text = builtins.toJSON {
    name = "uBlock0@raymondhill.net";
    description = "ignored";
    type = "storage";
    data =
      let
        # Suggested by Arkenfox
        urlShortener = "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt";
        # https://github.com/StevenBlack/hosts
        stevenBlackHosts = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        # these are for uBlock "medium" mode:
        # <https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode>
        # NOTE: modified to not break sites
        defaultFilteringString = ''
          behind-the-scene * * noop
          behind-the-scene * 1p-script noop
          behind-the-scene * 3p noop
          behind-the-scene * 3p-script noop
          behind-the-scene * 3p-frame noop
          behind-the-scene * image noop
          behind-the-scene * inline-script noop
        '';
      in
      {
        adminSettings = builtins.toJSON {
          userSettings = {
            advancedUserEnabled = true;
            dynamicFilteringEnabled = true;
            externalLists = lib.concatStringsSep "\n" [
              urlShortener
              stevenBlackHosts
            ];
            importedLists = [
              urlShortener
              stevenBlackHosts
            ];
          };
          selectedFilterLists = [
            # Built-in
            "user-filters"
            "ublock-filters"
            "ublock-badware"
            "ublock-privacy"
            "ublock-quick-fixes"
            "ublock-unbreak"
            # Ads
            "easylist"
            # Privacy
            "adguard-spyware"
            "adguard-spyware-url"
            "easyprivacy"
            # Malware domains
            "urlhaus-1"
            "curben-phishing"
            "curben-pup"
            # Annoyances
            "adguard-annoyance"
            "adguard-cookies"
            "adguard-mobile-app-banners"
            "adguard-popup-overlays"
            "adguard-social"
            "fanboy-thirdparty_social"
            "fanboy-cookiemonster"
            "fanboy-annoyance"
            "fanboy-social"
            "ublock-annoyances"
            "easylist-newsletters"
            # Multipurpose
            "dpollock-0"
            "plowe-0"
            # Custom
            urlShortener
            stevenBlackHosts
          ];
          dynamicFilteringString = ''
            ${defaultFilteringString}
          '';
        };
      };
  };
}
