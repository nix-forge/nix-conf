profileName:
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib.cust.firefox) toUserJS;
in
{
  programs.firefox.profiles.${profileName} = {
    extraConfig = lib.strings.concatLines [
      # Arkenfox
      (builtins.readFile "${pkgs.arkenfox-userjs}/user.js")

      # Betterfox
      (builtins.readFile "${inputs.firefox-betterfox}/Securefox.js")
      (builtins.readFile "${inputs.firefox-betterfox}/Peskyfox.js")
      (builtins.readFile "${inputs.firefox-betterfox}/Fastfox.js")
      (toUserJS {
        # TODO: This is an assumption that user is using a 120hz+ display change how this is implemented
        #
        #*************************************************************************************
        # OPTION: NATURAL SMOOTH SCROLLING V3 [MODIFIED]                                     *
        #*************************************************************************************
        # recommended for 120hz+ displays
        # largely matches Chrome flags: Windows Scrolling Personality and Smooth Scrolling
        "apz.overscroll.enabled" = true; # DEFAULT NON-LINUX
        "general.smoothScroll" = true; # DEFAULT
        "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
        "general.smoothScroll.msdPhysics.enabled" = true;
        "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
        "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
        "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
        "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2;
        "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
        "general.smoothScroll.currentVelocityWeighting" = 1;
        "general.smoothScroll.stopDecelerationWeighting" = 1;
        "mousewheel.default.delta_multiplier_y" = 300; # 250-400; adjust this number to your liking
      })

      # Overrides
      (toUserJS {
        # Start Page
        "browser.startup.homepage" = "about:home"; # start page is firefox home
        "browser.newtabpage.enabled" = true; # new tab leads to firefox home
        "browser.startup.homepage_override.mstone" = "ignore";
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
        "browser.messaging-system.whatsNewPanel.enabled" = false;
        "browser.urlbar.showSearchTerms.enabled" = false;

        # Enable WebGL
        "webgl.disabled" = false;

        # Fonts
        # From Firefox Arch Wiki: https://wiki.archlinux.org/title/Firefox#Font_troubleshooting
        "gfx.font_rendering.fontconfig.max_generic_substitutions" = 127; # Increase the maximum number of generic substitutions (127 is the highest possible value)
        "font.name-list.emoji" = "emoji"; # Use system emoji font
        "gfx.font_rendering.opentype_svg.enabled" = false; # Prevent Mozilla font from interfering with system emoji font

        # Downloads
        "browser.download.always_ask_before_handling_new_types" = false; # NOTE: This can be annoying when true as each new file type will asked where to be downloaded
        "browser.download.start_downloads_in_tmp_dir" = false; # (if changed true) This can be annoying when true as it will download to the temp directory making it harder to find the file

        # DNS
        "network.trr.mode" = 5; # use system DNS

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

      })
    ];
  };
}
