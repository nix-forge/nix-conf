{
  config,
  self,
  system,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isAarch64 isDarwin;
  enabled = isDarwin && isAarch64;
  app = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Xirp.app";
  nixPath = "/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
in
{
  home.packages = lib.mkIf enabled [ self.packages.${system}.xirp ];

  # GUI apps launched by LaunchServices do not inherit Home Manager's PATH.
  # Xirp discovers tmux and gh from its own environment, so make the copied
  # application bundle explicitly see the Nix-managed profile.
  home.activation.configureXirpDarwinApp = lib.mkIf enabled (
    lib.hm.dag.entryAfter [ "copyApps" ] ''
      xirpApp="${app}"
      plist="$xirpApp/Contents/Info.plist"

      test -d "$xirpApp"
      /usr/bin/codesign --verify --deep --strict "$xirpApp"
      /usr/bin/codesign --display --verbose=2 "$xirpApp" 2>&1 | grep -q 'Authority=Developer ID Application: Spotify (2FNC3A47ZF)'
      /usr/bin/codesign --display --verbose=2 "$xirpApp" 2>&1 | grep -q 'TeamIdentifier=2FNC3A47ZF'

      chmod -R u+w "$xirpApp"
      /usr/libexec/PlistBuddy -c 'Delete :LSEnvironment:PATH' "$plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c 'Add :LSEnvironment:PATH string ${nixPath}' "$plist"

      # Ad-hoc signing deliberately selects Xirp's manual updater, avoiding
      # Electron attempts to replace the immutable Nix-store source bundle.
      /usr/bin/codesign --force --deep --sign - "$xirpApp"
      /usr/bin/codesign --verify --deep --strict "$xirpApp"
      /usr/bin/codesign --display --verbose=2 "$xirpApp" 2>&1 | grep -q 'Signature=adhoc'
    ''
  );
}
