{
  inputs,
  myLib,
  pkgs,
  lib,
  config,
  self,
  system,
  ...
}:
let
  cfg = config.programs.spotify;
  managedPreferences = pkgs.writeText "spotify-managed-preferences" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (key: value: "${key}=${builtins.toJSON value}") cfg.preferences
    )
    + lib.optionalString (cfg.preferences != { }) "\n"
  );
  writeBashTemplate = myLib.writers.writeBashTemplate { inherit pkgs; };
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  spicePkgs = inputs.spicetify-nix.legacyPackages.${system};
  awkExe = lib.getExe pkgs.gawk;
  spicetifyPackage = pkgs.spicetify-cli;
  spotifyPackage = self.packages.${system}.spotify-spotx;
  metabrainzExtension = pkgs.metabrainz-spicetify-extension;
  spotifyDarwinInstallDir = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  spotifyDarwinApp = "${spotifyDarwinInstallDir}/Spotify.app";
  spotifyQuality = writeBashTemplate {
    name = "configure-spotify-quality.sh";
    src = ./spotify-assets/configure-spotify-quality.sh;
    replacements = {
      preferenceUpdater = ./spotify-assets/update-preferences.awk;
      inherit managedPreferences;
      pgrep = if isDarwin then "/usr/bin/pgrep" else lib.getExe' pkgs.procps "pgrep";
      mktemp = lib.getExe' pkgs.coreutils "mktemp";
      awk = awkExe;
      mv = lib.getExe' pkgs.coreutils "mv";
      rm = lib.getExe' pkgs.coreutils "rm";
      cmp = lib.getExe' pkgs.diffutils "cmp";
      spotifyPreferences =
        if isDarwin then
          "${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/prefs"} ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/Users"}/*-user/prefs"
        else
          "${lib.escapeShellArg "${config.xdg.configHome}/spotify/prefs"} ${lib.escapeShellArg "${config.xdg.configHome}/spotify/Users"}/*-user/prefs";
    };
  };
in
{
  options.programs.spotify = {
    disableAutostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable platform autostart registration and seed Spotify's matching startup preferences.";
    };
    preferences = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.oneOf [
          lib.types.bool
          lib.types.int
          lib.types.str
        ]
      );
      default = {
        "ui.track_notifications_enabled" = false;
        "audio.play_bitrate_enumeration" = 3;
        "audio.play_bitrate_non_metered_enumeration" = 3;
        "audio.allow_downgrade" = false;
      }
      // lib.optionalAttrs cfg.disableAutostart {
        "app.autostart-configured" = true;
        "app.autostart-mode" = "off";
      };
      description = "Managed Spotify preference values. Undeclared keys remain under the application's control.";
    };
  };
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];
  config = {
    assertions = [
      {
        assertion = lib.all (
          key: key != "" && !(lib.hasInfix "=" key || lib.hasInfix "\n" key || lib.hasInfix "\r" key)
        ) (lib.attrNames cfg.preferences);
        message = "Spotify preference names must be nonempty single-line keys without =.";
      }
    ];

    home.activation = {
      # spotify-spotx recursively signs the finished SpotX and Spicetify bundle
      # in its sandboxed build. Register the copied path without mutating it.
      registerSpotifyDarwinApp = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "copyApps" ] (
          (import ../../lib/templates/text.nix) ./spotify-assets/register-darwin-app.sh {
            lib_escapeShellArg_spotifyDarwinApp = lib.escapeShellArg spotifyDarwinApp;
          }
        )
      );

      # Spotify's account-specific prefs live beneath a runtime-created profile
      # directory. macOS also keeps startup policy in a parent `prefs` file.
      configureSpotifyQuality = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        (import ../../lib/templates/text.nix) ./spotify-assets/configure-quality.sh.in {
          script = lib.escapeShellArg (toString spotifyQuality);
        }
      );

      # Spotify's preference above prevents StartUpHelper from being registered
      # again. Keep launchd's existing user-level registration disabled too.
      disableSpotifyDarwinAutostart = lib.mkIf (isDarwin && cfg.disableAutostart) (
        lib.hm.dag.entryAfter [ "configureSpotifyQuality" "copyApps" ] (
          builtins.readFile ./spotify-assets/disable-autostart.sh
        )
      );
    };

    # Linux desktop sessions discover autostart applications through XDG. A
    # same-name user entry with `Hidden=true` overrides a vendor entry even if
    # Spotify or a package later supplies one.
    xdg.configFile."autostart/spotify.desktop" = lib.mkIf (isLinux && cfg.disableAutostart) {
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
        {
          src = metabrainzExtension;
          name = "metabrainz.js";
        }
      ];
    };
  };
}
