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
          "${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/prefs"} ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Application Support/Spotify/Users"}/*-user/prefs"
        else
          lib.escapeShellArg "${config.xdg.configHome}/spotify/prefs";
    };
  };
  palette = config.appearance.palette;
  isCarbonNeon = builtins.elem config.appearance.theme [
    "carbon-neon"
    "carbon-neon-oled"
  ];
  carbonNeonScheme = {
    inherit (palette) text;
    subtext = palette.muted;
    sidebar-text = palette.text;
    main = palette.surface;
    main-elevated = palette.surfaceRaised;
    highlight = palette.surfaceRaised;
    highlight-elevated = palette.surfaceHover;
    sidebar = palette.surface;
    player = palette.surface;
    card = palette.surfaceHover;
    shadow = "000000";
    selected-row = palette.muted;
    button = palette.accent;
    # Keep primary actions and selected playback states in Carbon's cyan rather
    # than Spotify's familiar green.  The latter is too close to Carbon's
    # reserved success colour and was the lime control shown in the screenshot.
    button-active = palette.accent;
    button-disabled = palette.outline;
    tab-active = palette.surfaceRaised;
    notification = palette.accent;
    notification-error = palette.danger;
    misc = palette.muted;
  };
  # `additionalCss` is an in-memory Home Manager value. Substituting its one
  # value during evaluation avoids trying to build a Linux derivation merely
  # to read CSS on the macOS deployment workstation.
  carbonNeonCss =
    let
      template = builtins.readFile ../../assets/spotify/carbon-neon.css;
      templateTokens = [
        "NIX_STYLIX_SANS_SERIF"
        "NIX_PALETTE_WARNING"
        "NIX_PALETTE_ACCENT_HOVER"
        "NIX_PALETTE_ACCENT_PRESSED"
      ];
      rendered = builtins.replaceStrings templateTokens [
        (builtins.toJSON config.stylix.fonts.sansSerif.name)
        "#${palette.warning}"
        "#${palette.accentHover}"
        "#${palette.accentPressed}"
      ] template;
    in
    assert lib.all (token: lib.hasInfix token template) templateTokens;
    assert lib.all (token: !(lib.hasInfix token rendered)) templateTokens;
    rendered;
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
  # directory. macOS also keeps startup policy in a parent `prefs` file, so
  # these are intentionally managed at activation rather than copied once.
  home.activation.configureSpotifyQuality = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    source ${spotifyQuality}
  '';

  # The macOS client has already registered its StartUpHelper as a background
  # login item. Spotify's preference above prevents it being registered again.
  # Keep launchd's user-level policy disabled as well, which controls the
  # registration that exists before this generation is activated.
  home.activation.disableSpotifyDarwinAutostart = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "configureSpotifyQuality" "copyApps" ] ''
      run /bin/launchctl disable "gui/$(/usr/bin/id -u)/com.spotify.client.startuphelper"
    ''
  );

  # Linux desktop sessions discover autostart applications through XDG. A
  # same-name user entry with `Hidden=true` overrides a vendor entry even if
  # Spotify or a package later supplies one.
  xdg.configFile."autostart/spotify.desktop" = lib.mkIf (!isDarwin) {
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
