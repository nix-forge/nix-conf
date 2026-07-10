{ pkgs }: {
  claude-desktop = pkgs.callPackage ./claude-desktop { };
  codex-app = pkgs.callPackage ./codex-app { };
  microsoft-teams = pkgs.callPackage ./microsoft-teams { };
  remindctl = pkgs.callPackage ./remindctl { };
  spotify-spotx = pkgs.callPackage ./spotify-spotx { };
  steam = pkgs.callPackage ./steam { };
  ttf-ms-win11-auto = pkgs.callPackage ./ttf-ms-win11-auto { };
  libreoffice = pkgs.callPackage ./libreoffice { };
}
