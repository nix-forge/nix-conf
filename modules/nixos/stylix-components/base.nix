{
  inputs,
  lib,
  config,
  ...
}:
let
  themeDefinitions = import ../../../themes { inherit inputs; };
in
{
  imports = [ inputs.stylix.nixosModules.stylix ];

  options.appearance.theme = lib.mkOption {
    type = lib.types.enum themeDefinitions.names;
    default = themeDefinitions.defaultName;
    description = "Shared dark theme for Stylix and native application integrations.";
  };

  config.stylix = {
    enable = true; # enable Stylix
    autoEnable = true; # auto enable Stylix for all applications

    polarity = "dark";

    # Keep the standalone Stylix component in step with the shared profile.
    base16Scheme = themeDefinitions.schemes.${config.appearance.theme};

    # Wallpaper
    # image = ./background.jpg;

    # Opacity
    opacity.terminal = 0.9;
  };
}
