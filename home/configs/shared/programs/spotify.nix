{ inputs, pkgs, config, ... }:
let spicePkgs = inputs.spicetify-nix.packages.${pkgs.system}.default;
in {
  # import the flake's module for your system
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  # TODO: find a way to fix this bug https://community.spotify.com/t5/Desktop-Linux/UI-Bug-Currently-playing-song-s-name-overlaps-with-Album-name/td-p/5618177
  #       I only have this problem when the gpu is Intel and not when it's Nvidia
  #       can add the --disable-gpu flag to spotify to fix it but then the gpu is not used at all

  # configure spicetify :)
  programs.spicetify = {
    theme = spicePkgs.themes.catppuccin;
    colorScheme = "mocha";

    # set the spotify and spicetify packages
    spotifyPackage = pkgs.spotify;
    spicetifyPackage = pkgs.spicetify-cli;

    # actually enable the installation of spotify and spicetify
    enable = true;

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      volumePercentage # Show volume percentage
      wikify # Show artists wiki page
      playlistIntersection # Show intersection of two playlists or songs unique to a playlist
      shuffle # Shuffle without bias
      seekSong # allows you to seek songs with arrow keys
      fullAlbumDate # show full album release date
    ];

    enabledCustomApps = with spicePkgs.apps; [ new-releases lyrics-plus ];

    #dontInstall = true;
  };

  # # Wrap spicetify with extra arguments and install package
  # # TODO: make this a little bit more elegantly and make sure I am wrapping the program correctly
  # # TODO: explain purpose of disable gpu flag
  # home.packages = let
  #   spicetify_pkg = config.programs.spicetify.spicedSpotify;
  #   spicetify_wrapped = pkgs.symlinkJoin {
  #     name = "spicetify-wrapped";
  #     paths = [
  #       (pkgs.writeShellScriptBin "spotify"
  #         "exec ${spicetify_pkg}/bin/spotify --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --disable-gpu")
  #       spicetify_pkg
  #     ];
  #   };
  # in [ spicetify_wrapped ];
}
