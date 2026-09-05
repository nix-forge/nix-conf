{ config, lib, ... }:
let
  cfg = config.programs.browserSuite.extensions;
  modeType = lib.types.enum [
    "allowed"
    "normal"
    "required"
  ];
  extensionType = lib.types.submodule (
    { config, ... }: {
      options = {
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            Packaged Firefox add-on. When present, its AMO metadata supplies the
            extension ID and slug unless either value is set explicitly.
          '';
        };

        id = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = if config.package == null then null else config.package.addonId or null;
          description = "Firefox extension ID.";
        };

        slug = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = if config.package == null then null else lib.getName config.package;
          description = "AMO slug used to install and update the extension.";
        };

        mode = lib.mkOption {
          type = modeType;
          default = "normal";
          description = "Whether the browser permits, installs, or requires this extension.";
        };

        privateBrowsing = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to grant private-browsing access.";
        };

        defaultArea = lib.mkOption {
          type = lib.types.enum [
            "navbar"
            "menupanel"
          ];
          default = "menupanel";
          description = "Initial toolbar location.";
        };

      };
    }
  );

  firefoxExtensions = cfg.shared // cfg.firefox;
  zenExtensions = cfg.shared // cfg.zen;
  uniqueIds = extensions: lib.length extensions == lib.length (lib.unique extensions);
  validExtension = extension: extension.id != null && extension.id != "*" && extension.slug != null;
in
{
  options.programs.browserSuite.extensions = {
    shared = lib.mkOption {
      type = lib.types.attrsOf extensionType;
      default = { };
      description = ''
        Extensions installed in both Firefox and Zen. Generated browser
        policies block and remove extensions outside the declared sets.
      '';
    };

    firefox = lib.mkOption {
      type = lib.types.attrsOf extensionType;
      default = { };
      description = "Extensions managed only in Firefox.";
    };

    zen = lib.mkOption {
      type = lib.types.attrsOf extensionType;
      default = { };
      description = "Extensions managed only in Zen.";
    };
  };

  config.assertions = [
    {
      assertion =
        lib.intersectLists (builtins.attrNames cfg.shared) (builtins.attrNames cfg.firefox) == [ ];
      message = "Shared and Firefox-only browser extensions must have distinct names.";
    }
    {
      assertion = lib.intersectLists (builtins.attrNames cfg.shared) (builtins.attrNames cfg.zen) == [ ];
      message = "Shared and Zen-only browser extensions must have distinct names.";
    }
    {
      assertion = uniqueIds (map (extension: extension.id) (builtins.attrValues firefoxExtensions));
      message = "Firefox browser extensions contain duplicate extension IDs.";
    }
    {
      assertion = uniqueIds (map (extension: extension.id) (builtins.attrValues zenExtensions));
      message = "Zen browser extensions contain duplicate extension IDs.";
    }
    {
      assertion = lib.all validExtension (
        builtins.attrValues firefoxExtensions ++ builtins.attrValues zenExtensions
      );
      message = "Browser extensions require an ID and slug and may not use the reserved `*` ID.";
    }
  ];
}
