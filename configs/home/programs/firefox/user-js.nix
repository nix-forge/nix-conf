profileName:
{ lib, inputs, ... }:
let
  toUserJS =
    kv:
    lib.concatLines (
      lib.mapAttrsToList (k: v: "user_pref(${builtins.toJSON k}, ${builtins.toJSON v});") kv
    );
in
{
  programs.firefox.profiles.${profileName} = {
    extraConfig = lib.strings.concatLines [
      # Arkenfox
      (builtins.readFile "${inputs.firefox-arkenfox}/user.js")

      # Betterfox
      # (builtins.readFile "${inputs.firefox-betterfox}/Securefox.js") # Using Arkenfox instead
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

        # Hardware Acceleration
        # TODO: Only add these if the use wants these settings so need to move somewhere else
        # These options are from the firefox Arch Wiki as well as the nvidia-vaapi-driver GitHub page
        # even though some of these options are from an Nvidia GPU guide they should work for most modern GPUs
        # https://wiki.archlinux.org/title/Firefox#Hardware_video_acceleration
        "gfx.webrender.all" = true; # Enforce hardware WebRender (Default false)
        # https://github.com/elFarto/nvidia-vaapi-driver/#firefox
        "media.ffmpeg.vaapi.enabled" = true; # Enable VA-API (Default false)
        "media.rdd-ffmpeg.enabled" = true; # Forces ffmpeg usage into the RDD process (Default true)
        "media.av1.enabled" = true; # Enable AV1 Decoding (already assuming new enough hardware) (Default true)
        "widget.dmabuf.force-enabled" = true; # Enforce DMABUF (Default false)

        # Enable WebGL
        "webgl.disabled" = false;

        # Fonts
        # From Firefox Arch Wiki: https://wiki.archlinux.org/title/Firefox#Font_troubleshooting
        "gfx.font_rendering.fontconfig.max_generic_substitutions" = 127; # Increase the maximum number of generic substitutions (127 is the highest possible value)
        "font.name-list.emoji" = "emoji"; # Use system emoji font
        "gfx.font_rendering.opentype_svg.enabled" = false; # Prevent Mozilla font from interfering with system emoji font

        # Firefox Accounts
        "identity.fxaccounts.enabled" = true;

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

        # Turn off resistFingerprinting so timezone and light/dark mode is correct
        "privacy.resistFingerprinting" = false;

        # Turn off fingerprinting protection to allow more fonts
        "browser.contentblocking.category" = "custom";
        "privacy.fingerprintingProtection" = false;

        # Fix bug with PDFs and Google Suite Apps like Google Docs being buggy
        # at the expense of hardware acceleration in certain situations with disabling canvas accelerated
        "gfx.canvas.accelerated" = false;
      })
    ];
  };
}
