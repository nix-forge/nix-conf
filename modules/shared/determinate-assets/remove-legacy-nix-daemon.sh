# shellcheck shell=bash
legacyNixDaemonPlist=/Library/LaunchDaemons/org.nixos.nix-daemon.plist
determinateNixDaemonPlist=/Library/LaunchDaemons/systems.determinate.nix-daemon.plist

if [ -e "$legacyNixDaemonPlist" ] && [ -e "$determinateNixDaemonPlist" ]; then
  launchctl bootout system/org.nixos.nix-daemon 2>/dev/null || true
  rm -f "$legacyNixDaemonPlist"
fi
