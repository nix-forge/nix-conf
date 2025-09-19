{
  tree,
  pkgs,
  config,
  ...
}@args:
let
  homeDir = tree.configs.home;
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
  # stylix # TODO: only enable if not enabled from the system do this in the stylix module
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
  # (programs.git { }) # TODO: add config to git module to allow not passing secrets info
  (install pkgs.git)

  programs.ssh
  # dev.docs
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

  (vscode.default "default")
  (vscode.settings "default")
  (vscode.keybinds "default")
  (vscode.ai.models "default")
  (vscode.languages.cpp "default")
  (vscode.languages.nix "default")
  (vscode.languages.web "default")
  (vscode.languages.python "default")
  (vscode.languages.bash "default")
  (vscode.languages.javascript "default")
  (vscode.languages.typescript "default")
  (vscode.languages.java "default")
  ((vscode.languages.docker "default") { enablePodman = true; })
  (vscode.languages.typst "default")
  (vscode.languages.solidity "default")
  (vscode.languages.sql "default")

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
  # (install inputs.geospatial-nix.packages.${system}.qgis)

  ## Video Games
  # gaming
  # (install pkgs.prismlauncher)
  # (install pkgs.lutris)

  ## Misc
  # { home.sessionVariables = sharedDir.env.wayland.default; }
  # wayland.electron-flags
]
