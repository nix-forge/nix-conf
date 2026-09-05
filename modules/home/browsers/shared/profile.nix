{ lib, ... }: {
  options.programs.browserSuite.shared.profile = {
    commonSettings = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = {
        # Use Firefox's maintained Strict ETP feature set. Resist Fingerprinting
        # remains off because it breaks locale, input, canvas and media behavior.
        "browser.contentblocking.category" = "strict";
        "privacy.globalprivacycontrol.enabled" = true;
        "privacy.resistFingerprinting" = false;

        # Keep browser security services and their recovery paths intact.
        "browser.safebrowsing.downloads.remote.enabled" = true;
        "security.OCSP.enabled" = 1;
        "security.OCSP.require" = false;
        "browser.xul.error_pages.expert_bad_cert" = false;
        "full-screen-api.warning.timeout" = 3000;

        # Useful Gecko features that the previous preset stack disabled.
        "browser.profiles.enabled" = true;
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;
        "browser.search.separatePrivateDefault.ui.enabled" = true;
        "browser.translations.enable" = true;
        "reader.parse-on-load.enabled" = true;
        "media.videocontrols.picture-in-picture.enabled" = true;
        "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;

        # Clear, recoverable tab and document behavior.
        "browser.sessionstore.resume_from_crash" = true;
        "browser.tabs.warnOnClose" = true;
        "browser.tabs.closeWindowWithLastTab" = false;
        "browser.tabs.insertAfterCurrent" = true;
        "browser.tabs.loadBookmarksInTabs" = true;
        "browser.download.open_pdf_attachments_inline" = true;
        "pdfjs.disabled" = false;
        "pdfjs.enableScripting" = false;
        "findbar.highlightAll" = true;
        "network.IDN_show_punycode" = true;
      };
    };

    scrolling = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      internal = true;
      readOnly = true;
      default = {
        default = { };

        instant = {
          "apz.overscroll.enabled" = true;
          "general.smoothScroll" = true;
          "mousewheel.default.delta_multiplier_y" = 275;
          "general.smoothScroll.msdPhysics.enabled" = false;
        };

        natural = {
          "apz.overscroll.enabled" = true;
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
          "general.smoothScroll.msdPhysics.enabled" = true;
          "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
          "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2;
          "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
          "general.smoothScroll.currentVelocityWeighting" = "1";
          "general.smoothScroll.stopDecelerationWeighting" = "1";
          "mousewheel.default.delta_multiplier_y" = 300;
        };

        sharpen = {
          "apz.overscroll.enabled" = true;
          "general.smoothScroll" = true;
          "mousewheel.min_line_scroll_amount" = 10;
          "general.smoothScroll.mouseWheel.durationMinMS" = 80;
          "general.smoothScroll.currentVelocityWeighting" = "0.15";
          "general.smoothScroll.stopDecelerationWeighting" = "0.6";
          "general.smoothScroll.msdPhysics.enabled" = false;
        };

        smooth = {
          "apz.overscroll.enabled" = true;
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.enabled" = true;
          "mousewheel.default.delta_multiplier_y" = 300;
        };
      };
    };
  };
}
