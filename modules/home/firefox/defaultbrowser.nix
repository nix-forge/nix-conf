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

  firefoxAppPath =
    let
      homeDir = config.home.homeDirectory;
    in
    if config.targets.darwin.copyApps.enable then
      "${homeDir}/${config.targets.darwin.copyApps.directory}/Firefox.app"
    else if config.targets.darwin.linkApps.enable then
      "${homeDir}/${config.targets.darwin.linkApps.directory}/Firefox.app"
    else
      null;

  refreshDeps = [
    "installPackages"
  ]
  ++ lib.optionals config.targets.darwin.copyApps.enable [ "copyApps" ]
  ++ lib.optionals (!config.targets.darwin.copyApps.enable) [ "linkGeneration" ];

  setDefaultBrowserHelper = pkgs.replaceVarsWith {
    name = "hm-set-default-firefox";
    src = ./defaultbrowser.sh;
    dir = "bin";
    isExecutable = true;
    replacements = {
      inherit
        awkExe
        defaultBrowserExe
        firefoxAppPath
        lsregisterExe
        plistBuddyExe
        ;
    };
  };
in
{
  home.activation = lib.mkIf isDarwin {
    setDefaultBrowser = lib.hm.dag.entryAfter refreshDeps ''
      ${lib.getExe' setDefaultBrowserHelper "hm-set-default-firefox"}
    '';
  };

  home.sessionVariables.BROWSER = lib.mkDefault "firefox";
}
