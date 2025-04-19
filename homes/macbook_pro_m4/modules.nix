{
  tree,
  pkgs,
  inputs,
  self,
  ...
}:
let
  homeDir = tree.configs.home;
  sharedDir = tree.configs.shared;
  install = pkg: { home.packages = [ pkg ]; };
in
with (homeDir // homeDir.programs // homeDir.programs.editors);
[
  { home.stateVersion = "25.05"; }
  ## Base
  # base
  # ./hardware
  # ./secrets.nix
  # (base.mime { })

  ## Theming
  # theming.basic
  # theming.gtk
  # {
  #   # Firefox
  #   # TODO: rethink if this is the best place to add this option as it becomes a manual process
  #   stylix.targets.firefox.profileNames = [ "default" ];
  # }

  ## Web Browsers
  programs.firefox
  (
    # TODO: move this to the firefox module for AArch64 systems
    {
      config,
      pkgs,
      ...
    }:
    {
      programs.firefox.package = pkgs.firefox.override (old: {
        # cfg = old.cfg or { } // fcfg;
        extraPolicies = (old.extraPolicies or { }) // config.programs.firefox.policies;
        pkcs11Modules = (old.pkcs11Modules or [ ]) ++ config.programs.firefox.pkcs11Modules;
      });
    }
  )

  # { programs.chromium.enable = true; }

  ## Shell Environments
  shells.zsh

  ## Terminal Emulators
  # programs.kitty

  ## Development Tools
  # programs.git
  # programs.ssh
  # dev.docs
  dev.direnv
  # dev.github-cli
  dev.nix-formatter

  ## Code Editors
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
  vscode.languages.docker
  vscode.languages.spice

  ## Communication
  # (install pkgs.discord)
  (install self.packages.${pkgs.system}.webcord)
  # (install pkgs.signal-desktop)
  # (install pkgs.slack)

  ## Media Consumption
  programs.spotify
]
