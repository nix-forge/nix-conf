{
  lib,
  config,
  inputs,
  ...
}:
let
  profile = "${config.home.username}.default";

  toUserJS =
    kv:
    lib.concatLines (
      lib.mapAttrsToList (k: v: "user_pref(${builtins.toJSON k}, ${builtins.toJSON v});") kv
    );
in
{
  programs.firefox.profiles.${profile} = {
    extraConfig = lib.strings.concatLines [
      (toUserJS {
        # GeoLocation
        "geo.provider.network.url" = "https://location.services.mozilla.com/v1/geolocate?key=%MOZILLA_API_KEY%";
        "geo.provider.ms-windows-location" = false;
        "geo.provider.use_corelocation" = false;
        "geo.provider.use_gpsd" = false;
        "geo.provider.use_geoclue" = false;

        # Disable extension recommendations
        "extensions.getAddons.showPane" = false;
        "extensions.htmlaboutaddons.recommendations.enabled" = false;
        "browser.discovery.enabled" = false;
        "browser.shopping.experience2023.enabled" = false;

        # Disable telemetry
        "datareporting.policy.dataSubmissionEnabled" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.server" = "data:,";
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.newProfilePing.enabled" = false;
        "toolkit.telemetry.shutdownPingSender.enabled" = false;
        "toolkit.telemetry.updatePing.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.firstShutdownPing.enabled" = false;
        "toolkit.telemetry.coverage.opt-out" = true;
        "toolkit.coverage.opt-out" = true;
        "toolkit.coverage.endpoint.base" = "";
        "browser.ping-centre.telemetry" = false;
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;

        # Disable user experiments and studies
        "app.shield.optoutstudies.enabled" = false;
        "app.normandy.enabled" = false;
        "app.normandy.api_url" = "";

        # Disable crash reports
        "breakpad.reportURL" = "";
        "browser.tabs.crashReporting.sendReport" = false;
        "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;

        # Other
        "captivedetect.canonicalURL" = "";
        "network.capaptive-portal-service.enabled" = false;
        "network.connectivity-service.enabled" = false;

        # Safe Browsing
        "browser.safebrowsing.downloads.remote.enabled" = false;

        # Block Implicit Outbound
        "network.prefetch-next" = false;
        "network.dns.disablePrefetch" = true;
        "network.predictor.enabled" = false;
        "network.predictor.enable-prefetch" = false;
        "network.http.speculative-parallel-limit" = 0;
        "browser.places.speculativeConnect.enabled" = false;

        # DNS
        "network.proxy.socks_remote_dns" = false; # user system DNS
        "network.file.disable_unc_paths" = true;
        "network.gio.supported-protocols" = "";
        "network.trr.mode" = 5; # use system DNS

        # LOCATION BAR / SEARCH BAR / SUGGESTIONS / HISTORY
        "browser.urlbar.speculativeConnect.enabled" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.search.suggest.enabled" = false;
        "browser.urlbar.suggest.searches" = false;
        "browser.urlbar.trending.featureGate" = false;
        "browser.urlbar.addons.featureGate" = false;
        "browser.urlbar.mdn.featureGate" = false;
        "browser.urlbar.pocket.featureGate" = false;
        "browser.urlbar.weather.featureGate" = false;

        # Disable Auto Form Fill
        "browser.formfill.enable" = false;

        # Seperate Private Search Engines
        "browser.search.separatePrivateDefault" = true;
        "browser.search.separatePrivateDefault.ui.enabled" = true;

        # Passwords
        "signon.autofillForms" = false;
        "signon.formlessCapture.enabled" = false;
        "network.auth.subresource-http-auth-allow" = 1;

        # Disk Avoidance
        "browser.cache.disk.enable" = true; # NOTE: (if changed false) then performance could be impacted
        "browser.privatebrowsing.forceMediaMemoryCache" = true;
        "media.memory_cache_max_size" = 65536;
        "browser.sessionstore.privacy_level" = 2;
        "toolkit.winRegisterApplicationRestart" = false;
        "browser.shell.shortcutFavicons" = false;

        # HTTPS
        "security.ssl.require_safe_negotiation" = true;
        "security.tls.enable_0rtt_data" = false;
        "security.OCSP.enabled" = 1;
        "security.OCSP.require" = true;

        # CERTS / HTKP (HTTP Public Key Pinning)
        "security.cert_pinning.enforcement_level" = 2;
        "security.remote_settings.crlite_filters.enabled" = true;
        "security.pki.crlite_mode" = 2;

        # Mixed Content
        "dom.security.https_only_mode" = true;
        "dom.scurity.https_only_mode_send_http_background_request" = false;

        # UI
        "security.ssl.treat_unsafe_negotiation_as_broken" = true;
        "browser.xul.error_pages.expert_bad_cert" = true;

        # Referers
        "network.http.referer.XOriginTrimmingPolicy" = 2;

        # Containers
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;

        # Plugins / Media ? WebRTC
        "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
        "media.peerconnection.ice.default_address_only" = true;

        # DOM
        "dom.disable_window_move_resize" = true;

        # Miscellanious
        "browser.download.start_downloads_in_tmp_dir" = false; # (if changed true) This can be annoying when true as it will download to the temp directory making it harder to find the file
        "browser.helperApps.deleteTempFileOnExit" = true;
        "browser.uitour.enabled" = false;
        "devtools.debugger.remote-enabled" = false;
        "permissions.manager.defaultsUrl" = "";
        "webchannel.allowObject.urlWhitelist" = "";
        "network.IDN_show_punycode" = true;
        "pdfjs.disabled" = false;

        # Enable RFP
        "privacy.resistFingerprinting" = false; # NOTE: (if changed true) This causes issues with google suite apps like google docs and causes blurry fonts
        "privacy.resistFingerprinting.block_mozAddonManager" = true;
        "privacy.resistFingerprinting.letterboxing" = false; # NOTE: (if changed true) This can be annoying as it has small borders around the window
        "browser.display.use_system_colors" = false; # Disable Using System Colors
        "widget.non-native-theme.enabled" = true;
        "browser.link.open_newwindow" = 3;
        "browser.link.open_newwindow.restriction" = 0;

        # Enforce Settings
        "extensions.blocklist.enabled" = true; # enforce Firefox blocklist
        "network.http.referer.spoofSource" = false; # enforce no referer spoofing
        "security.dialog_enable_delay" = 1000; # enforce security dialog delay
        "privacy.firstparty.isolate" = false; # enforce no first party isolation
        "extensions.webcompat.enable_shims" = true; # enforce smartblock shims
        "security.tls.version.enable-deprecated" = false; # enforce no deprecated TLS
        "extensions.webcompat-reporter.enabled" = false; # enforce no webcompat reporter
        "extensions.quarantinedDomains.enabled" = true; # enforce quarantined domains
      })

      # Betterfox
      (builtins.readFile "${inputs.firefox-betterfox}/Securefox.js")
      (builtins.readFile "${inputs.firefox-betterfox}/Peskyfox.js")
      (builtins.readFile "${inputs.firefox-betterfox}/Fastfox.js")
      (toUserJS {
        /**
          **************************************************************************************
          * OPTION: NATURAL SMOOTH SCROLLING V3 [MODIFIED]                                      *
          ***************************************************************************************
        */
        # credit: https://github.com/AveYo/fox/blob/cf56d1194f4e5958169f9cf335cd175daa48d349/Natural%20Smooth%20Scrolling%20for%20user.js
        # recommended for 120hz+ displays
        # largely matches Chrome flags: Windows Scrolling Personality and Smooth Scrolling
        "apz.overscroll.enabled" = true; # DEFAULT NON-LINUX
        "general.smoothScroll" = true; # DEFAULT
        "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
        "general.smoothScroll.msdPhysics.enabled" = true;
        "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
        "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
        "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
        "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2.0;
        "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
        "general.smoothScroll.currentVelocityWeighting" = 1.0;
        "general.smoothScroll.stopDecelerationWeighting" = 1.0;
        "mousewheel.default.delta_multiplier_y" = 300; # 250-400; adjust this number to your liking
      })

      # Overides
      (toUserJS {
        # Start Page
        "browser.startup.homepage_override.mstone" = "ignore";
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
        "browser.messaging-system.whatsNewPanel.enabled" = false;
        "browser.urlbar.showSearchTerms.enabled" = false;

        # Hardware Acceleration
        # These options are from the firefox Arch Wiki as well as the nvidia-vaapi-driver GitHub page
        # even though some of these options are from an Nvidia GPU guide they should work for most modern GPUs
        # https://wiki.archlinux.org/title/Firefox#Hardware_video_acceleration
        # https://github.com/elFarto/nvidia-vaapi-driver/#firefox
        "gfx.webrender.all" = true; # Enforce hardware WebRender (Default false)
        "media.ffmpeg.vaapi.enabled" = true; # Enable VA-API (Default false)
        "media.rdd-ffmpeg.enabled" = true; # Forces ffmpeg usage into the RDD process (Default true)
        "media.av1.enabled" = true; # Enable AV1 Decoding (already assumming new enough hardware) (Default true)
        "widget.dmabuf.force-enabled" = true; # Enforce DMABUF (Default false)
        "gfx.canvas.accelerated" = true; # Enforce hardware acceleration (Default true)

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
      })

      # Firefox Lepton UI
      (builtins.readFile "${inputs.firefox-lepton-ui}/user.js")

    ];
  };
}
