{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  awkExe = lib.getExe pkgs.gawk;
  defaultBrowserExe = lib.getExe pkgs.defaultbrowser;
  lsregisterExe = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
  plistBuddyExe = "/usr/libexec/PlistBuddy";

  zenAppPath =
    let
      homeDir = config.home.homeDirectory;
      appName = "Zen Browser (Twilight).app";
    in
    if config.targets.darwin.copyApps.enable then
      "${homeDir}/${config.targets.darwin.copyApps.directory}/${appName}"
    else if config.targets.darwin.linkApps.enable then
      "${homeDir}/${config.targets.darwin.linkApps.directory}/${appName}"
    else
      null;

  refreshDeps = [
    "installPackages"
  ]
  ++ lib.optionals config.targets.darwin.copyApps.enable [ "copyApps" ]
  ++ lib.optionals (!config.targets.darwin.copyApps.enable) [ "linkGeneration" ];

  setDefaultBrowserHelper = pkgs.replaceVarsWith {
    name = "hm-set-default-zen-browser";
    src = ./defaultbrowser.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      inherit
        awkExe
        defaultBrowserExe
        lsregisterExe
        plistBuddyExe
        zenAppPath
        ;
    };
  };
in
{
  programs.zen-browser.setAsDefaultBrowser = true;

  home.activation = lib.mkIf (isDarwin && config.programs.zen-browser.enable) {
    setDefaultBrowser = lib.hm.dag.entryAfter refreshDeps ''
      ${lib.getExe' setDefaultBrowserHelper "hm-set-default-zen-browser"}
    '';
  };

  home.sessionVariables.BROWSER = lib.mkDefault "zen-twilight";
}
