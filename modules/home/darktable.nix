{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  # Do not inherit a host-wide CUDA setting here. Darktable's GPU path brings
  # a very large CUDA/OpenCV closure into every Home Manager generation; CPU
  # rendering remains fully functional, while a GPU build can be a deliberate
  # host-specific override when it is worth that tradeoff.
  cpuPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
      cudaSupport = false;
    };
  };
  inherit (cpuPkgs) darktable;

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
      <string>${darktable.version}</string>
      <key>CFBundleVersion</key>
      <string>${darktable.version}</string>
      <key>LSMinimumSystemVersion</key>
      <string>11.0</string>
      <key>NSHighResolutionCapable</key>
      <true/>
    </dict>
    </plist>
  '';

  darktableApp = pkgs.runCommand "darktable-app-${darktable.version}" { } ''
    app="$out/Applications/darktable.app"

    install -d "$app/Contents/MacOS" "$app/Contents/Resources"
    ln -s "${darktable}/bin/darktable" "$app/Contents/MacOS/darktable"
    cp "${darktable}/share/icons/hicolor/256x256/apps/darktable.png" \
      "$app/Contents/Resources/darktable.png"
    cp "${infoPlist}" "$app/Contents/Info.plist"
  '';
in
{
  home.packages = [ darktable ] ++ lib.optionals isDarwin [ darktableApp ];
}
