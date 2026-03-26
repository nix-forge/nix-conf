{ pkgs }:
{
  claude-desktop = pkgs.callPackage ./claude-desktop { };
  codex-app = pkgs.callPackage ./codex-app { };
  opencode-cursor = pkgs.callPackage ./opencode-cursor { };
  steam = pkgs.callPackage ./steam { };
  ttf-ms-win11-auto = pkgs.callPackage ./ttf-ms-win11-auto { };
}
