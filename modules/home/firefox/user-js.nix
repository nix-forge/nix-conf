{
  lib,
  myLib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (myLib.firefox) toUserJS;
in
{
  programs.firefox.profiles.default = {
    extraConfig = lib.strings.concatLines (
      [
        # Arkenfox
        (builtins.readFile "${pkgs.arkenfox-userjs}/user.js")

        # Betterfox
        (builtins.readFile "${inputs.firefox-betterfox}/Securefox.js")
        (builtins.readFile "${inputs.firefox-betterfox}/Peskyfox.js")
        (builtins.readFile "${inputs.firefox-betterfox}/Fastfox.js")
      ]
      ++ [
        # Overrides
        (toUserJS {
          # Start Page
          "browser.startup.homepage" = "about:home"; # start page is firefox home
          "browser.newtabpage.enabled" = true; # new tab leads to firefox home
          "browser.startup.homepage_override.mstone" = "ignore";

          # Fonts
          "gfx.font_rendering.fontconfig.max_generic_substitutions" = 127; # Increase the maximum number of generic substitutions (127 is the highest possible value)
          "font.name-list.emoji" = "emoji"; # Use system emoji font
          "gfx.font_rendering.opentype_svg.enabled" = true;
          "privacy.fingerprintingProtection.overrides" = "-FontVisibilityBaseSystem,-FontVisibilityLangPack";

          # Downloads
          "browser.download.always_ask_before_handling_new_types" = false; # NOTE: This can be annoying when true as each new file type will asked where to be downloaded
          "browser.download.start_downloads_in_tmp_dir" = false; # (if changed true) This can be annoying when true as it will download to the temp directory making it harder to find the file

          # PDF
          "browser.download.open_pdf_attachments_inline" = false; # Download PDFs instead of opening them inline

          # Disable LetterBoxing
          "privacy.resistFingerprinting.letterboxing" = false; # NOTE: (if changed true) This can be annoying as it has small borders around the window

          # Session Restore
          "browser.startup.page" = 3;

          # Disable Shutdown Sanitization
          "privacy.sanitize.sanitizeOnShutdown" = false;

          # Turn off fingerprinting protection to increase stability
          "privacy.resistFingerprinting" = false;
          "browser.contentblocking.category" = "custom";
          "privacy.fingerprintingProtection" = false;

          # Disable new profiles from being created and switching between profiles
          "browser.profiles.enabled" = false;
        })
      ]
    );
  };
}
