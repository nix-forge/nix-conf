{ config, pkgs, ... }: {
  macos.dockItems = {
    enable = true;
    mode = "authoritative";

    persistentApps = [
      { package = config.programs.ghostty.package; }
      { package = config.programs.vscode.package; }
      { package = config.programs.t3code.package; }

      { spacer.small = true; }

      { package = config.programs.zen-browser.package; }

      { spacer.small = true; }

      { app = "/System/Applications/Messages.app"; }
      # { app = "/Applications/‎WhatsApp.app"; }
      { app = "/System/Applications/Phone.app"; }
      { app = "/System/Applications/FaceTime.app"; }
      { package = config.programs.vesktop.package; }

      { spacer.small = true; }

      { package = config.programs.spicetify.spicedSpotify; }
      { package = pkgs.feishin; }
      { package = pkgs.moonfin; }
      { app = "/System/Applications/Music.app"; }

      { spacer.small = true; }

      { app = "/System/Applications/Calendar.app"; }
      { app = "/System/Applications/Reminders.app"; }
      { app = "/System/Applications/Notes.app"; }
      # { hmApp = "Notion"; }
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
