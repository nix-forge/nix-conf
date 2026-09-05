{ inputs, pkgs, ... }:
let
  rakutenExtension = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.ebates;
in
{
  programs.browserSuite = {
    extensions.zen.rakuten = {
      package = rakutenExtension;
      mode = "allowed";
      defaultArea = "navbar";
    };

    zen.shopping = {
      enable = true;
      startUrl = "https://www.cashbackmonitor.com/";
      extensions = [ "rakuten" ];
    };
  };

  programs.zen-browser.profiles.shopping = {
    pinsForce = false;
    pins = {
      "Cashback Monitor" = {
        id = "3cd71f74-c69e-4013-a522-c51be3ffd6d5";
        url = "https://www.cashbackmonitor.com/";
        position = 100;
        isEssential = true;
      };
      Rakuten = {
        id = "185950ab-914a-41d9-9f5b-9a7edc5e860a";
        url = "https://www.rakuten.com/";
        position = 200;
      };
      TopCashback = {
        id = "42477649-cea2-4701-8e9b-1a95e6f7456f";
        url = "https://www.topcashback.com/";
        position = 300;
      };
      BeFrugal = {
        id = "1d796618-4acd-4f93-ae6e-c878159ccca6";
        url = "https://www.befrugal.com/";
        position = 400;
      };
    };
  };
}
