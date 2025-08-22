{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};

  spotifyPackageDarwin = pkgs.spotify.overrideAttrs (old: {
    postInstall = (old.postInstall or '''') + ''
      # Path to the Spotify binary after install
      binary="$out/Applications/Spotify.app/Contents/MacOS/Spotify"

      # Apply the Perl patch
      ${pkgs.perl}/bin/perl -pi -w -e 's|\x64(?=\x65\x73\x6B\x74\x6F\x70\x2D\x75\x70)|\x00|g' "$binary"
    '';
  });
in
{
  # import the flake's module for your system
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  # create a home manager activation script to prevent spotify from asking to update
  home.activation.removeSpotifyDarwinAutoUpdate = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      autoUpdatePath="${config.home.homeDirectory}/Library/Application Support/Spotify/PersistentCache/Update"
      if [ -d "$autoUpdatePath" ] && [ "$(ls -A "$autoUpdatePath")" ]; then
        rm -rf "$autoUpdatePath"
      fi
    ''
  );

  # configure spicetify
  programs.spicetify = {
    spotifyPackage = if isDarwin then spotifyPackageDarwin else pkgs.spotify;

    theme = lib.mkForce spicePkgs.themes.comfy;
    colorScheme = lib.mkForce "Spotify";

    # actually enable the installation of spotify and spicetify
    enable = true;

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      volumePercentage
      shuffle
      copyLyrics
      fullAlbumDate
    ];
  };
}
