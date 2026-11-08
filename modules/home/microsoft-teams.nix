{
  self,
  system,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./macos/application-capabilities.nix ];
  home.packages = lib.mkIf (self.packages.${system} ? microsoft-teams) [
    self.packages.${system}.microsoft-teams
  ];

  macos.applicationCapabilities.apps.teams = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = lib.mkDefault (self.packages.${system} ? microsoft-teams);
    bundle = "Microsoft Teams.app";
    bundleId = "com.microsoft.teams2";
    features.sharing = {
      enable = lib.mkDefault false;
      service = "screen-recording";
      reason = "Present a selected window in Teams";
      source = "https://support.microsoft.com/en-us/teams/meetings/present-content-in-microsoft-teams-meetings";
      instruction = "Share a harmless test window through Teams itself and verify the other participant receives it.";
    };
  };
}
