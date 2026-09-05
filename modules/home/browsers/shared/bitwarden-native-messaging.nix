{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  enabled = lib.hasAttrByPath [ "programs" "bitwardenDesktop" "package" ] options;
  desktopPackage = lib.attrByPath [
    "programs"
    "bitwardenDesktop"
    "package"
  ] pkgs.bitwarden-desktop config;
  darwinAppPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Bitwarden.app";
  proxyPath =
    if isDarwin then
      "${darwinAppPath}/Contents/MacOS/desktop_proxy"
    else
      "${desktopPackage}/libexec/desktop_proxy";

  geckoManifestData = {
    name = "com.8bit.bitwarden";
    description = "Bitwarden desktop <-> browser bridge";
    path = proxyPath;
    type = "stdio";
    allowed_extensions = [ "{446900e4-71c2-419f-a6a7-df9c091e268b}" ];
  };
  geckoManifest = pkgs.writeText "com.8bit.bitwarden-gecko.json" (builtins.toJSON geckoManifestData);

  chromiumManifestData = {
    name = "com.8bit.bitwarden";
    description = "Bitwarden desktop <-> browser bridge";
    path = proxyPath;
    type = "stdio";
    allowed_origins = [ "chrome-extension://nngceckbapebfimnlniiiahkandclblb/" ];
  };
  chromiumManifest = pkgs.writeText "com.8bit.bitwarden-chromium.json" (
    builtins.toJSON chromiumManifestData
  );

  geckoTargets =
    if isDarwin then
      [
        "${config.home.homeDirectory}/Library/Application Support/Mozilla/NativeMessagingHosts/com.8bit.bitwarden.json"
        "${config.home.homeDirectory}/Library/Application Support/Zen/NativeMessagingHosts/com.8bit.bitwarden.json"
      ]
    else
      [ "${config.home.homeDirectory}/.mozilla/native-messaging-hosts/com.8bit.bitwarden.json" ];

  chromiumTargets =
    if isDarwin then
      [
        "${config.home.homeDirectory}/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.8bit.bitwarden.json"
        "${config.home.homeDirectory}/Library/Application Support/Chromium/NativeMessagingHosts/com.8bit.bitwarden.json"
        "${config.home.homeDirectory}/Library/Application Support/net.imput.helium/NativeMessagingHosts/com.8bit.bitwarden.json"
      ]
    else
      [
        "${config.home.homeDirectory}/.config/google-chrome/NativeMessagingHosts/com.8bit.bitwarden.json"
        "${config.home.homeDirectory}/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json"
        "${config.home.homeDirectory}/.config/net.imput.helium/NativeMessagingHosts/com.8bit.bitwarden.json"
      ];

  mkdir = if isDarwin then "/bin/mkdir" else lib.getExe' pkgs.coreutils "mkdir";
  install = if isDarwin then "/usr/bin/install" else lib.getExe' pkgs.coreutils "install";
  installManifest = source: target: ''
    run ${mkdir} -p ${lib.escapeShellArg (dirOf target)}
    run ${install} -m 0600 ${lib.escapeShellArg source} ${lib.escapeShellArg target}
  '';
  activationDeps = [ "writeBoundary" ] ++ lib.optionals isDarwin [ "copyApps" ];
in
{
  options.programs.browserSuite.shared.bitwarden = {
    geckoManifest = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = geckoManifestData;
    };

    chromiumManifest = lib.mkOption {
      type = lib.types.attrs;
      internal = true;
      readOnly = true;
      default = chromiumManifestData;
    };
  };

  config = {
    # Keep these files mutable so Bitwarden can refresh them when the user
    # approves browser integration. Each activation restores the exact, minimal
    # extension allowlists and the current immutable proxy path.
    home.activation.installBitwardenNativeMessaging = lib.mkIf enabled (
      lib.hm.dag.entryAfter activationDeps (
        lib.concatMapStrings (installManifest geckoManifest) geckoTargets
        + lib.concatMapStrings (installManifest chromiumManifest) chromiumTargets
      )
    );

    assertions = [
      {
        assertion = isLinux || isDarwin;
        message = "Bitwarden browser native messaging is supported only on Linux and Darwin.";
      }
    ];
  };
}
