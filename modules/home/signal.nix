{ pkgs, lib, ... }: {
  imports = [ ./macos/application-capabilities.nix ];
  home.packages = [ pkgs.signal-desktop ];
  macos.applicationCapabilities.apps.signal = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = lib.mkDefault true;
    bundle = "Signal.app";
    bundleId = "org.whispersystems.signal-desktop";
    features = {
      voice = {
        enable = lib.mkDefault false;
        service = "microphone";
        reason = "Speak in Signal calls";
        source = "https://support.signal.org/hc/en-us/articles/360007062172-Signal-Permissions-OS-Notification-Settings";
        instruction = "Place a Signal test call and confirm audio with a consenting participant.";
      };
      video = {
        enable = lib.mkDefault false;
        service = "camera";
        reason = "Use Signal video calls";
        source = "https://support.signal.org/hc/en-us/articles/360007062172-Signal-Permissions-OS-Notification-Settings";
        instruction = "Preview the camera during a Signal test call.";
      };
      sharing = {
        enable = lib.mkDefault false;
        service = "screen-recording";
        reason = "Share a window in Signal";
        source = "https://support.signal.org/hc/en-us/articles/360007062172-Signal-Permissions-OS-Notification-Settings";
        instruction = "Share a harmless test window during a Signal call.";
      };
    };
  };
}
