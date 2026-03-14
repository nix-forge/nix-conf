{
  config,
  lib,
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
    };

    bindings = {
      "Ctrl+1" = "script-message toggle-anime-fast";
      "Ctrl+2" = "script-message toggle-anime-hq";
      "Ctrl+3" = "script-message toggle-smooth-motion";
      "Ctrl+4" = "script-message toggle-max-anime-mode";
      "Ctrl+0" = "script-message reset-anime-modes";
    };
  };

  xdg.configFile."mpv/scripts/anime-toggle.lua".source = ./mpv-anime-toggle.lua;
}
