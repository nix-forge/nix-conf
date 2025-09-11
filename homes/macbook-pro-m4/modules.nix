{
  tree,
  pkgs,
  inputs,
  config,
  self,
  ...
}@args:
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
  (base.xdg { uid = 501; })
  # ./hardware
  ./secrets.nix
  # (base.mime { })

  ## Theming
  stylix
  (stylix.targets.firefox config.home.username)

  ## Desktop Environment
  window-managers.aerospace

  ## Web Browsers
  (programs.defaultbrowser "firefox")
  (programs.firefox.default config.home.username)
  (import ./firefox.nix config.home.username)

  ## Shell Environments
  shells.nushell
  shells.aliases
  shells.starship
  shells.zoxide
  shells.carapace
  shells.eza
  # shells.tmux

  ## Terminal Emulators
  (varBin "TERMINAL" "ghostty")
  programs.ghostty

  ## Development Tools
  (programs.git { emailConfig = import ./gitEmailConfig.nix args; })
  programs.ssh
  ./ssh.nix
  # dev.docs
  dev.direnv
  dev.github-cli
  dev.nix-formatter
  dev.podman
  (install pkgs.just)
  # { services.ollama.enable = true; }

  ## Code Editors
  (varBin "EDITOR" "nvim")
  (install pkgs.neovim)
  (install pkgs.code-cursor)

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
  # (install pkgs.discord)
  (install pkgs.slack)
  (install pkgs.zoom-us)
  # (install self.packages.${system}.webcord)
  # (install pkgs.signal-desktop)

  ## Video Games
  (install pkgs.prismlauncher)

  ## Media Consumption
  # programs.spotify
]
