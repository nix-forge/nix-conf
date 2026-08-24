{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  inherit (config.home) homeDirectory;
in
{
  xdg = {
    enable = true;

    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    stateHome = "${homeDirectory}/.local/state";
    cacheHome = "${homeDirectory}/.cache";

    userDirs = {
      enable = true;
      # Preserve the behavior from the original Home Manager generation.
      # This explicit value avoids an implicit compatibility default changing
      # on a future Home Manager upgrade.
      setSessionVariables = true;
      createDirectories = true;
      extraConfig =
        lib.optionalAttrs isDarwin {
          # macOS tools and the Dock expose source work through Developer.
          DEVELOPER = "${homeDirectory}/Developer";
        }
        // lib.optionalAttrs (!isDarwin) {
          # xdg-user-dirs 0.20 standardizes this general project location.
          PROJECTS = "${homeDirectory}/Projects";
        }
        // {
          SCREENSHOTS = "${config.xdg.userDirs.pictures}/Screenshots";
        };
      videos = lib.mkIf isDarwin (lib.mkDefault "${homeDirectory}/Movies");
      templates = lib.mkIf isDarwin (lib.mkDefault null);
    };
  };

  home.preferXdgDirectories = config.xdg.enable;

  # Preserve the pre-26.05 Zsh layout explicitly.  Moving this to XDG is a
  # separate migration because it changes where interactive shell files live.
  programs.zsh.dotDir = config.home.homeDirectory;
}
