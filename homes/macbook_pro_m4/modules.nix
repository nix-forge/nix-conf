{
  tree,
  pkgs,
  inputs,
  config,
  self,
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
  # ./hardware
  # ./secrets.nix
  # (base.mime { })

  ## Theming
  stylix
  stylix.targets.firefox

  ## Desktop Environment
  window-managers.aerospace

  ## Web Browsers
  (programs.defaultbrowser "firefox")
  programs.firefox

  ## Shell Environments
  shells.nushell
  shells.aliases
  shells.starship
  shells.zoxide
  shells.carapace
  shells.eza
  # shells.tmux

  ## Terminal Emulators
  programs.ghostty

  ## Development Tools
  programs.git
  programs.ssh
  # dev.docs
  dev.direnv
  dev.github-cli
  dev.nix-formatter
  dev.podman

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

  ## Communication
  (install pkgs.discord)
  (install pkgs.slack)
  (install pkgs.zoom-us)
  # (install self.packages.${pkgs.system}.webcord)
  # (install pkgs.signal-desktop)

  ## Media Consumption
  programs.spotify
]
