{
  tree,
  pkgs,
  inputs,
  config,
  ...
}:
let
  homeDir = tree.configs.home;
  sharedDir = tree.configs.shared;
  install = pkg: { home.packages = [ pkg ]; };
  var = envVar: val: { home.sessionVariables.${envVar} = val; };
  varBin = envVar: val: var envVar "/etc/profiles/per-user/${config.home.username}/bin/${val}";
in
with (homeDir // homeDir.programs // homeDir.programs.editors);
[
  ## Base
  base.version
  base.fonts
  # ./secrets.nix
  (base.mime { })

  ## Theming
  theming.basic
  theming.gtk
  # stylix
  (stylix.targets.firefox config.home.username)

  ## Desktop Environment
  desktop-envs.hyprland
  ./hyprland
  { stylix.targets.hyprland.enable = false; }

  ## Desktop Applications
  programs.rofi
  programs.waybar
  # programs.ags
  (install pkgs.nautilus)
  # (install pkgs.apostrophe)
  (install pkgs.motrix)
  (install pkgs.pinta)

  ## Utility
  programs.gparted

  ## Web Browsers
  (programs.defaultbrowser "firefox")
  (programs.firefox.default config.home.username)
  { programs.chromium.enable = true; }

  ## Shell Environments
  shells.nushell
  shells.aliases
  shells.starship
  shells.zoxide
  shells.carapace
  shells.eza

  ## Terminal Emulators
  (varBin "TERMINAL" "ghostty")
  programs.ghostty

  ## Development Tools
  programs.git
  programs.ssh
  dev.docs
  dev.direnv
  dev.github-cli
  dev.nix-formatter
  dev.podman
  (install pkgs.just)
  { services.ollama.enable = true; }

  ## Development Languages
  dev.languages.c
  dev.languages.python

  ## Code Editors
  (varBin "EDITOR" "nvim")
  (install pkgs.neovim)
  vscode.settings
  vscode.languages.cpp
  vscode.languages.esp-idf
  vscode.languages.nix
  vscode.languages.web
  vscode.languages.python
  vscode.languages.bash
  vscode.languages.verilog
  vscode.languages.javascript
  vscode.languages.typescript
  (vscode.languages.docker { enablePodman = true; })
  vscode.languages.spice
  vscode.languages.matlab
  vscode.languages.typst

  ## Communication
  (install pkgs.discord)
  (install pkgs.slack)
  (install pkgs.zoom-us)

  ## Media Consumption
  programs.spotify
  # (install pkgs.rhythmbox)

  ## Office Software
  programs.libreoffice
  (install pkgs.obsidian)
  (install pkgs.kdePackages.okular)
  # (install inputs.geospatial-nix.packages.${pkgs.system}.qgis)

  ## Video Games
  # gaming
  # (install pkgs.prismlauncher)
  # (install pkgs.lutris)

  ## Misc
  # { home.sessionVariables = sharedDir.env.wayland.default; }
  # wayland.electron-flags
]
