{ lib, ... }: {
  options.homelab.desktopAurral.qualityProfile = lib.mkOption {
    description = "Managed Lidarr quality policy used by the desktop Aurral integration.";
    default = { };
    type = lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "Aurral High Quality";
          description = "Name of the declaratively managed quality profile.";
        };
        templateName = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "Lossless";
          description = "Existing Lidarr template used when creating the managed profile, including its cutoff.";
        };
        allowedQualityNames = lib.mkOption {
          type = lib.types.addCheck (lib.types.listOf lib.types.nonEmptyStr) (names: names != [ ]);
          default = [
            "FLAC"
            "FLAC 24bit"
            "ALAC"
            "ALAC 24bit"
            "MP3-320"
            "MP3-256"
            "MP3-VBR-V0"
            "AAC-320"
            "AAC-256"
            "AAC-VBR"
          ];
          description = "Lidarr quality names accepted by the managed profile.";
        };
        cutoffQualityName = lib.mkOption {
          type = lib.types.nullOr lib.types.nonEmptyStr;
          default = null;
          description = "Allowed quality whose API identifier sets the upgrade cutoff; null preserves the template cutoff.";
        };
        upgradeAllowed = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether Lidarr upgrades releases in the managed profile.";
        };
      };
    };
  };
  options.homelab.desktopAurral.onboarding = {
    metadataProfileName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "Standard";
      description = "Existing Lidarr metadata profile used for first-run onboarding.";
    };
    defaultMonitorOption = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "future";
      description = "Initial Lidarr monitoring choice; later UI choices are preserved.";
    };
    searchOnAdd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Initial Lidarr search-on-add policy.";
    };
    localNetworkBypass = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Initial Aurral local-network authentication bypass policy.";
    };
  };
  options.homelab.desktopAurral.slskd = {
    priority = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Initial Soulseek acquisition priority.";
    };
    preferredFormat = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "flac";
      description = "Initial Soulseek format preference.";
    };
    preferredFormatStrict = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the initial Soulseek format preference is required.";
    };
  };

}
