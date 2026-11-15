{
  config,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  animeFastShaders = [
    "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl"
    "${pkgs.anime4k}/Anime4K_Restore_CNN_M.glsl"
    "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl"
    "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl"
    "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl"
    "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_S.glsl"
  ];

  animeHqShaders = [
    "${pkgs.anime4k}/Anime4K_Clamp_Highlights.glsl"
    "${pkgs.anime4k}/Anime4K_Restore_CNN_VL.glsl"
    "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_VL.glsl"
    "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x2.glsl"
    "${pkgs.anime4k}/Anime4K_AutoDownscalePre_x4.glsl"
    "${pkgs.anime4k}/Anime4K_Upscale_CNN_x2_M.glsl"
  ];

  mkShaderList = shaders: lib.concatStringsSep ":" shaders;
in
{
  # Captions need scene-independent contrast rather than desktop theme colors.
  stylix.targets.mpv.enable = false;

  programs.mpv = {
    enable = true;

    defaultProfiles = [ "high-quality" ];

    scripts =
      with pkgs.mpvScripts;
      [
        uosc
        thumbfast
      ]
      ++ lib.optionals isLinux [ mpris ];

    config = {
      hwdec = "auto-safe";

      deband = true;
      "deband-iterations" = 2;
      "deband-threshold" = 32;
      "deband-range" = 16;

      "osd-bar" = false;
      "screenshot-format" = "png";
      "autofit-larger" = "100%x100%";

      "save-position-on-quit" = true;
      "keep-open" = true;

      # Plain text uses a compact outline; authored ASS signs and fonts
      # keep their layout. See docs/research/media-captions-research.md.
      # Keep the caption font explicit when Stylix also provides a font.
      "sub-font" = lib.mkForce "Noto Sans";
      "sub-font-size" = 41;
      "sub-bold" = false;
      "sub-border-style" = "outline-and-shadow";
      "sub-color" = "#FFFFFFFF";
      "sub-border-color" = "#FF000000";
      "sub-border-size" = 2;
      "sub-shadow-offset" = 0;
      "sub-back-color" = "#00000000";
      "sub-margin-y" = 28;
      "sub-margin-x" = 36;
      "sub-ass-override" = "no";
      "embeddedfonts" = true;
      "sub-auto" = "fuzzy";
      slang = "en,eng";
    };

    scriptOpts = {
      thumbfast = {
        mpv_path = "${config.programs.mpv.finalPackage}/bin/mpv";
      };
    };

    profiles = {
      anime-fast = {
        "profile-desc" = "Anime4K fast preset";
        "profile-restore" = "copy";
        "glsl-shaders" = mkShaderList animeFastShaders;
      };

      anime-hq = {
        "profile-desc" = "Anime4K HQ preset";
        "profile-restore" = "copy";
        "glsl-shaders" = mkShaderList animeHqShaders;
      };

      smooth-motion = {
        "profile-desc" = "High FPS interpolation";
        "profile-restore" = "copy";
        "video-sync" = "display-resample";
        interpolation = true;
        tscale = "oversample";
      };

      captions-balanced = {
        "profile-desc" = "Readable text captions, preserving authored ASS";
        "sub-ass-override" = "no";
        "sub-scale" = 1;
        "sub-pos" = 100;
        "sub-border-style" = "outline-and-shadow";
        "sub-shadow-offset" = 0;
        "sub-back-color" = "#00000000";
      };
      captions-outline = {
        "profile-desc" = "Text captions with outline only";
        "sub-border-style" = "outline-and-shadow";
        "sub-shadow-offset" = 0;
        "sub-back-color" = "#00000000";
      };
      captions-contrast = {
        "profile-desc" = "Text captions on an opaque black box";
        "sub-shadow-offset" = 4;
        "sub-border-style" = "background-box";
        "sub-back-color" = "#FF000000";
      };
    };

    bindings = {
      "Ctrl+1" = "script-message toggle-anime-fast";
      "Ctrl+2" = "script-message toggle-anime-hq";
      "Ctrl+3" = "script-message toggle-smooth-motion";
      "Ctrl+4" = "script-message toggle-max-anime-mode";
      "Ctrl+0" = "script-message reset-anime-modes";
      "Alt+1" = "apply-profile captions-balanced; show-text 'Captions: balanced / authored ASS'";
      "Alt+2" = "apply-profile captions-contrast; show-text 'Captions: opaque background for plain text'";
      "Alt+4" = "apply-profile captions-outline; show-text 'Captions: outline only'";
      "Alt+3" = "cycle-values sub-ass-override no force; show-text 'ASS override: \${sub-ass-override}'";
      "Alt+UP" = "add sub-pos -1; show-text 'Caption position: \${sub-pos}'";
      "Alt+DOWN" = "add sub-pos 1; show-text 'Caption position: \${sub-pos}'";
      "Alt+=" = "add sub-scale 0.1; show-text 'Caption scale: \${sub-scale}'";
      "Alt+-" = "add sub-scale -0.1; show-text 'Caption scale: \${sub-scale}'";
    };
  };

  xdg.configFile."mpv/scripts/anime-toggle.lua".source =
    myLib.writers.checkLuaFile { inherit pkgs; }
      {
        name = "mpv-anime-toggle.lua";
        src = ./mpv-anime-toggle.lua;
        lua = config.programs.mpv.finalPackage.unwrapped.lua;
        readGlobals = [ "mp" ];
      };
}
