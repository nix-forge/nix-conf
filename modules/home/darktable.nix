{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  infoPlist = pkgs.writeText "darktable-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleDisplayName</key>
      <string>darktable</string>
      <key>CFBundleExecutable</key>
      <string>darktable</string>
      <key>CFBundleIconFile</key>
      <string>darktable.png</string>
      <key>CFBundleIdentifier</key>
      <string>org.darktable.darktable</string>
      <key>CFBundleName</key>
      <string>darktable</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>${pkgs.darktable.version}</string>
      <key>CFBundleVersion</key>
      <string>${pkgs.darktable.version}</string>
      <key>LSMinimumSystemVersion</key>
      <string>11.0</string>
      <key>NSHighResolutionCapable</key>
      <true/>
    </dict>
    </plist>
  '';

  darktableApp = pkgs.runCommand "darktable-app-${pkgs.darktable.version}" { } ''
    app="$out/Applications/darktable.app"

    install -d "$app/Contents/MacOS" "$app/Contents/Resources"
    ln -s "${pkgs.darktable}/bin/darktable" "$app/Contents/MacOS/darktable"
    cp "${pkgs.darktable}/share/icons/hicolor/256x256/apps/darktable.png" \
      "$app/Contents/Resources/darktable.png"
    cp "${infoPlist}" "$app/Contents/Info.plist"
  '';
in
{
  home.packages = [ pkgs.darktable ] ++ lib.optionals isDarwin [ darktableApp ];
}
