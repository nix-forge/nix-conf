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
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  spicePkgs = inputs.spicetify-nix.legacyPackages.${system};
  awkExe = lib.getExe pkgs.gawk;
  spicetifyPackage = pkgs.spicetify-cli;
  spotifyPackage = if isDarwin then self.packages.${system}.spotify-spotx else pkgs.spotify;
  spotifyEntitlements = if isDarwin then spotifyPackage.passthru.entitlements else null;
  spotifyDarwinInstallDir = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}";
  spotifyDarwinApp = "${spotifyDarwinInstallDir}/Spotify.app";
  spotifyRepair =
    if isDarwin then
      pkgs.replaceVarsWith {
        name = "repair-spotify-darwin-app.sh";
        src = ./scripts/repair-spotify-darwin-app.sh;
        replacements = {
          chmod = "/bin/chmod";
          xattr = "/usr/bin/xattr";
          codesign = "/usr/bin/codesign";
          lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
          spotifyApp = lib.escapeShellArg spotifyDarwinApp;
          # Keep this store-valued replacement unescaped so `replaceVarsWith`
          # retains Nix's dependency context for the generated script.
          inherit spotifyEntitlements;
        };
      }
    else
      null;
  spotifyQuality = pkgs.replaceVarsWith {
    name = "configure-spotify-quality.sh";
    src = ./scripts/configure-spotify-quality.sh;
    replacements = {
      pgrep = "/usr/bin/pgrep";
      mktemp = lib.getExe' pkgs.coreutils "mktemp";
      awk = awkExe;
      mv = lib.getExe' pkgs.coreutils "mv";
      spotifyPreferences =
        if isDarwin then
          "${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/Users"}/*-user/prefs"
        else
          lib.escapeShellArg "${config.xdg.configHome}/spotify/prefs";
    };
  };
  isCarbonNeon = builtins.elem config.appearance.theme [
    "carbon-neon"
    "carbon-neon-oled"
  ];
  carbonNeonScheme = with config.lib.stylix.colors; {
    text = base05;
    subtext = base04;
    sidebar-text = base05;
    main = base00;
    main-elevated = base01;
    highlight = base01;
    highlight-elevated = base02;
    sidebar = base00;
    player = base00;
    card = base02;
    shadow = "000000";
    selected-row = base04;
    button = base0D;
    # Keep primary actions and selected playback states in Carbon's cyan rather
    # than Spotify's familiar green.  The latter is too close to Carbon's
    # reserved success colour and was the lime control shown in the screenshot.
    button-active = base0D;
    button-disabled = base03;
    tab-active = base01;
    notification = base0D;
    notification-error = base08;
    misc = base04;
  };
  carbonNeonCss = builtins.readFile ../../assets/spotify/carbon-neon.css;
  carbonNeonTheme = spicePkgs.themes.default // {
    name = "CarbonNeon";
    additionalCss = carbonNeonCss;
  };
  theme =
    if config.appearance.theme == "catppuccin-mocha" then
      {
        theme = spicePkgs.themes.catppuccin;
        colorScheme = "mocha";
      }
    else if config.appearance.theme == "gruvbox-dark-medium" then
      {
        # Spicetify's upstream Text theme includes the canonical Gruvbox
        # Medium palette, including its #282828 background.
        theme = spicePkgs.themes.text;
        colorScheme = "Gruvbox";
      }
    else
      {
        # The base theme supplies Spicetify's layout hooks.  The local CSS also
        # maps Spotify's newer native tokens to the generated Carbon palette.
        theme = carbonNeonTheme;
        colorScheme = "custom";
      };
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  # The patched application and its Spicetify configuration are produced in a
  # sandboxed build. The final macOS bundle envelope can only be signed after
  # Home Manager copies the mutable app out of the store; darwin.sigtool does
  # not support that host-only `codesign --deep` operation in the sandbox.
  home.activation.repairSpotifyDarwinAppSignature = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "copyApps" ] ''
      source ${spotifyRepair}
    ''
  );

  # Spotify's account-specific prefs live beneath a runtime-created profile
  # directory, so they are the one intentionally runtime configuration step.
  home.activation.configureSpotifyQuality = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source ${spotifyQuality}
  '';

  programs.spicetify = {
    enable = true;
    inherit spotifyPackage;
    inherit spicetifyPackage;

    # Use the maintained native port for the selected shared palette.
    theme = lib.mkForce theme.theme;
    colorScheme = lib.mkForce theme.colorScheme;
    customColorScheme = lib.mkIf isCarbonNeon carbonNeonScheme;

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      volumePercentage
      shuffle
      copyLyrics
      fullAlbumDate
    ];
  };
}
