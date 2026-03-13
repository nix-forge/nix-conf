{ config, ... }:
{
  macos.dockItems = {
    enable = true;

    persistentApps = [
      { hmApp = "Ghostty"; }
      { hmApp = "Visual Studio Code"; }
      { app = "/Applications/Codex.app"; }

      { spacer.small = true; }

      { hmApp = "Firefox"; }

      { spacer.small = true; }

      { app = "/System/Applications/Messages.app"; }
      { app = "/Applications/WhatsApp.app"; }
      { app = "/System/Applications/Phone.app"; }
      { app = "/System/Applications/FaceTime.app"; }
      { hmApp = "Vesktop"; }

      { spacer.small = true; }

      { hmApp = "Spotify"; }
      { app = "/System/Applications/Music.app"; }

      { spacer.small = true; }

      { app = "/System/Applications/Calendar.app"; }
      { app = "/System/Applications/Reminders.app"; }
      { app = "/System/Applications/Notes.app"; }
      { hmApp = "Notion"; }
      { app = "/System/Applications/Preview.app"; }

      { spacer.small = true; }

      { app = "/System/Applications/System Settings.app"; }
      { app = "/System/Applications/Utilities/Activity Monitor.app"; }
    ];

    persistentOthers = [
      {
        folder = {
          path = config.xdg.userDirs.extraConfig.DEVELOPER;
          displayAs = "folder";
          showAs = "list";
          arrangement = "name";
        };
      }
      {
        folder = {
          path = config.xdg.userDirs.download;
          displayAs = "stack";
          showAs = "grid";
          arrangement = "date-added";
        };
      }
    ];
  };
}
