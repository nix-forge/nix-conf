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

  infoPlist = (pkgs.formats.plist { }).generate "darktable-Info.plist" {
    CFBundleDevelopmentRegion = "en";
    CFBundleDisplayName = "darktable";
    CFBundleExecutable = "darktable";
    CFBundleIconFile = "darktable.png";
    CFBundleIdentifier = "org.darktable.darktable";
    CFBundleName = "darktable";
    CFBundlePackageType = "APPL";
    CFBundleShortVersionString = darktable.version;
    CFBundleVersion = darktable.version;
    LSMinimumSystemVersion = "11.0";
    NSHighResolutionCapable = true;
  };

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
