{
  config,
  lib,
  pkgs,
  ...
}:
let
  suite = config.programs.browserSuite;
  inherit (suite) scrolling;
  inherit (suite.shared) profile search;
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  gecko = (import ../shared/.gecko.nix { inherit lib; }) {
    inherit suite;
    browser = "firefox";
    inherit (config.programs.firefox) profiles;
    configDirectory = "${config.home.homeDirectory}/Library/Application Support/Firefox";
  };
in
{
  imports = [ ../shared ];

  programs.firefox = {
    enable = true;
    # Preserve existing Linux profiles when Home Manager changes its default.
    configPath = lib.mkIf (!isDarwin) ".mozilla/firefox";
    # Policies live in the macOS defaults domain, so Darwin does not need a
    # wrapFirefox rebuild that strips Mozilla's application signature.
    package = lib.mkIf isDarwin pkgs.firefox-bin-unwrapped;
    inherit (gecko) policies;

    profiles.default = {
      id = 0;
      isDefault = true;
      userContent = builtins.readFile ../shared/emoji-presentation.css;
      settings = profile.commonSettings // profile.scrolling.${scrolling};
      search = {
        force = true;
        engines = search.commonEngines;
      };
    };
  };

  home.activation.reconcileFirefoxInstallRegistry = lib.mkIf isDarwin (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${gecko.reconcileInstallRegistry}
    ''
  );
}
