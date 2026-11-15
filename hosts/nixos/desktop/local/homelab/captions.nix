{ config, lib, ... }:
let
  captions = {
    assDirectPlay = true;
    subtitlesUseEmbeddedStyles = true;
    subtitlesUseEmbeddedFontSizes = true;
    subtitlesTextColor = "#FFFFFFFF";
    subtitleTextStrokeColor = "#FF000000";
    subtitlesBackgroundColor = "#00000000";
    subtitlesTextWeight = 400;
    subtitlesOffsetPosition = 0.04;
  };
  secret = name: config.nixSeal.secrets."homelab-jellyfin-${name}".path;
in
{
  homelab.optional.jellyfinCaptions = {
    enable = config.homelab.optional.jellyfinPlugins.moonbase.enable;
    adminUsernameFile = secret "admin-username";
    adminPasswordFile = secret "admin-password";
    usernameFiles = [
      (secret "admin-username")
      (secret "viewer-username")
    ];
    readyUnits = [ "homelab-integrate-jellyfin.service" ];
    revision = "v3";
    profiles = {
      global = captions // {
        subtitlesTextSize = 18.0;
      };
      desktop = captions // {
        subtitlesTextSize = 18.0;
      };
      mobile = captions // {
        subtitlesTextSize = 18.0;
      };
      tv = captions // {
        subtitlesTextSize = 20.0;
      };
    };
    previousRevision = "v2";
    previousProfiles = lib.genAttrs [ "global" "desktop" "mobile" "tv" ] (
      profile:
      captions
      // {
        subtitlesTextSize =
          {
            global = 24.0;
            desktop = 24.0;
            mobile = 20.0;
            tv = 28.0;
          }
          .${profile};
        subtitlesTextWeight = 700;
        subtitlesBackgroundColor = "#BF000000";
      }
    );
  };
}
