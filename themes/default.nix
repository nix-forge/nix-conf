{ inputs }: {
  defaultName = "carbon-neon";

  names = [
    "catppuccin-mocha"
    "gruvbox-dark-medium"
    "carbon-neon"
    "carbon-neon-oled"
  ];

  schemes = {
    catppuccin-mocha = inputs.stylix.inputs.tinted-schemes + "/base16/catppuccin-mocha.yaml";
    gruvbox-dark-medium = inputs.stylix.inputs.tinted-schemes + "/base16/gruvbox-dark-medium.yaml";
    carbon-neon = ./carbon-neon.yaml;
    carbon-neon-oled = ./carbon-neon-oled.yaml;
  };
}
