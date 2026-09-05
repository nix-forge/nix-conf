{ config, ... }:
let
  generalSpace = "121ff65b-88e8-4ac8-b1cc-3ed7f91ab56d";
  developmentSpace = "5b0dbf3e-f3ee-4534-971f-965d69f503a0";
  extensionGroups = config.programs.browserSuite.extensions;
  ids = builtins.mapAttrs (_: extension: extension.id) (
    extensionGroups.shared // extensionGroups.zen
  );
in
{
  programs.zen-browser.profiles.default = {
    settings = {
      "zen.urlbar.behavior" = "float";
      "zen.view.compact.hide-tabbar" = true;
      "zen.welcome-screen.seen" = true;
    };

    # These declarations upsert the named items while preserving spaces and
    # pins created in Zen itself.
    spacesForce = true;
    pinsForce = true;
    pinsForceAction = "demote";

    spaces = {
      General = {
        id = generalSpace;
        position = 1000;
        icon = "🏠";
        pins.ChatGPT = {
          id = "1075c95f-3fed-44fa-8742-929e9aa3117c";
          url = "https://chatgpt.com/";
          position = 100;
          isEssential = true;
        };
      };

      Development = {
        id = developmentSpace;
        position = 2000;
        icon = "💻";
      };
    };

    spaceRouting = {
      force = false;
      defaultExternalRoute = "most-recent-space";
    };

    extensionButtons = {
      "nav-bar" = [
        ids.ublockOrigin
        ids.bitwarden
      ];
      "unified-extensions-area" = [
        ids.karakeep
        ids.sponsorBlock
        ids.refinedGitHub
        ids.simplifyJobs
      ];
    };

    keyboardShortcuts = [
      {
        id = "zen-compact-mode-toggle";
        key = "c";
        modifiers = {
          control = true;
          alt = true;
        };
      }
    ];
  };
}
