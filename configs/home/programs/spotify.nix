{
  inputs,
  pkgs,
  config,
  ...
}:
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
in
{
  # import the flake's module for your system
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  # configure spicetify :)
  programs.spicetify = {
    theme = spicePkgs.themes.default;
    colorScheme = "Ocean";

    # actually enable the installation of spotify and spicetify
    enable = true;

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      volumePercentage
      shuffle
    ];

    # dontInstall = true;
  };

  # # Wrap spicetify with extra arguments and install package
  # TODO: find a better way to fix this bug https://community.spotify.com/t5/Desktop-Linux/UI-Bug-Currently-playing-song-s-name-overlaps-with-Album-name/td-p/5618177
  #       I only have this problem when the gpu is Intel and not when it's Nvidia
  #       can add the --disable-gpu flag to spotify to fix it but then the gpu is not used at all
  # # TODO: make this a little bit more elegantly and make sure I am wrapping the program correctly
  # home.packages =
  #   let
  #     spicetify_pkg = config.programs.spicetify.spicedSpotify;
  #     spicetify_wrapped = pkgs.symlinkJoin {
  #       name = "spicetify-wrapped";
  #       paths = [
  #         (pkgs.writeShellScriptBin "spotify" "exec ${spicetify_pkg}/bin/spotify --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime --disable-gpu")
  #         spicetify_pkg
  #       ];
  #     };
  #   in
  #   [ spicetify_wrapped ];
}

# { pkgs, ... }:
# {
#   home.packages = [
#     # (pkgs.nur.repos.nltch.spotify-adblock.override {
#     #   inherit (pkgs)
#     #     spotify
#     #     stdenv
#     #     rustPlatform
#     #     fetchFromGitHub
#     #     xorg
#     #     zip
#     #     unzip
#     #     ;
#     # })
#     pkgs.spotify
#   ];
# }
