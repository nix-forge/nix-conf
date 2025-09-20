profileName:
{
  scrollPreset ? "natural",
  ...
}:
{
  lib,
  system,
  inputs,
  self,
  ...
}:
let
  inherit (lib.cust.firefox) toUserJS;
  arkenfoxPackage = self.packages.${system}.arkenfox-user-js;
  arkenfoxUserJs = arkenfoxPackage.passthru.userJsSrc;
  presets = import ./scrolling { inherit lib; };
  resolvePreset =
    preset:
    if preset == null then
      null
    else if builtins.isString preset then
      let
        found = lib.attrByPath [ preset ] null presets;
      in
      assert lib.assertMsg (found != null) "Unknown Smoothfox preset \"${preset}\".";
      found
    else
      assert lib.assertMsg (
        builtins.isAttrs preset && preset ? extraConfig
      ) "scrollPreset must be null, a preset name, or a preset record with `extraConfig`.";
      preset;
  selectedPreset = resolvePreset scrollPreset;
  scrollSnippets = if selectedPreset == null then [ ] else [ selectedPreset.extraConfig ];
in
{
  programs.firefox.profiles.${profileName} = {
    extraConfig = lib.strings.concatLines (
      [
        # Arkenfox
        (builtins.readFile arkenfoxUserJs)

        # Betterfox
        (builtins.readFile "${inputs.firefox-betterfox}/Securefox.js")
        (builtins.readFile "${inputs.firefox-betterfox}/Peskyfox.js")
        (builtins.readFile "${inputs.firefox-betterfox}/Fastfox.js")
      ]
      ++ scrollSnippets
      ++ [
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
      ]
    );
  };
}
