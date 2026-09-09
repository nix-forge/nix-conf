{
  inputs,
  pkgs,
  lib,
  config,
  self,
  system,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  spicePkgs = inputs.spicetify-nix.legacyPackages.${system};
  awkExe = lib.getExe pkgs.gawk;
  spicetifyPackage = pkgs.spicetify-cli;
  spotifyPackage = self.packages.${system}.spotify-spotx;
  spotifyDarwinInstallDir = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  spotifyDarwinApp = "${spotifyDarwinInstallDir}/Spotify.app";
  spotifyQuality = pkgs.replaceVarsWith {
    name = "configure-spotify-quality.sh";
    src = ./scripts/configure-spotify-quality.sh;
    replacements = {
      pgrep = if isDarwin then "/usr/bin/pgrep" else lib.getExe' pkgs.procps "pgrep";
      mktemp = lib.getExe' pkgs.coreutils "mktemp";
      awk = awkExe;
      mv = lib.getExe' pkgs.coreutils "mv";
      spotifyPreferences =
        if isDarwin then
          "${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/prefs"} ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/Users"}/*-user/prefs"
        else
          "${lib.escapeShellArg "${config.xdg.configHome}/spotify/prefs"} ${lib.escapeShellArg "${config.xdg.configHome}/spotify/Users"}/*-user/prefs";
    };
  };
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  home.activation = {
    # spotify-spotx recursively signs the finished SpotX and Spicetify bundle
    # in its sandboxed build. Register the copied path without mutating it.
    registerSpotifyDarwinApp = lib.mkIf isDarwin (
      lib.hm.dag.entryAfter [ "copyApps" ] ''
        spotifyApp=${lib.escapeShellArg spotifyDarwinApp}
        if [[ -d "$spotifyApp" ]]; then
          run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f "$spotifyApp"
        fi
      ''
    );

    # Spotify's account-specific prefs live beneath a runtime-created profile
    # directory. macOS also keeps startup policy in a parent `prefs` file.
    configureSpotifyQuality = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      source ${spotifyQuality}
    '';

    # Spotify's preference above prevents StartUpHelper from being registered
    # again. Keep launchd's existing user-level registration disabled too.
    disableSpotifyDarwinAutostart = lib.mkIf isDarwin (
      lib.hm.dag.entryAfter [ "configureSpotifyQuality" "copyApps" ] ''
        run /bin/launchctl disable "gui/$(/usr/bin/id -u)/com.spotify.client.startuphelper"
      ''
    );
  };

  # Linux desktop sessions discover autostart applications through XDG. A
  # same-name user entry with `Hidden=true` overrides a vendor entry even if
  # Spotify or a package later supplies one.
  xdg.configFile."autostart/spotify.desktop" = lib.mkIf isLinux {
    text = ''
      [Desktop Entry]
      Type=Application
      Hidden=true
    '';
  };

  programs.spicetify = {
    enable = true;
    inherit spotifyPackage;
    inherit spicetifyPackage;
    experimentalFeatures = false;

    enabledExtensions = with spicePkgs.extensions; [
      volumePercentage
      shuffle
      copyLyrics
      fullAlbumDate
    ];
  };
}
