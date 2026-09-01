{
  inputs,
  lib,
  config,
  ...
}:
{
  imports = [ inputs.stylix.nixosModules.stylix ];

  options.appearance.theme = lib.mkOption {
    type = lib.types.enum [
      "catppuccin-mocha"
      "gruvbox-dark-medium"
      "carbon-neon"
      "carbon-neon-oled"
    ];
    default = "carbon-neon";
    description = "Shared dark theme for Stylix and native application integrations.";
  };

  config.stylix = {
    enable = true; # enable Stylix
    autoEnable = true; # auto enable Stylix for all applications

    polarity = "dark";

    # Keep the standalone Stylix component in step with the shared profile.
    base16Scheme =
      {
        catppuccin-mocha = inputs.stylix.inputs.tinted-schemes + "/base16/catppuccin-mocha.yaml";
        gruvbox-dark-medium = inputs.stylix.inputs.tinted-schemes + "/base16/gruvbox-dark-medium.yaml";
        carbon-neon = ../../../themes/carbon-neon.yaml;
        carbon-neon-oled = ../../../themes/carbon-neon-oled.yaml;
      }
      .${config.appearance.theme};

    # Wallpaper
    # image = ./background.jpg;

    # Opacity
    opacity.terminal = 0.9;
  };
}
