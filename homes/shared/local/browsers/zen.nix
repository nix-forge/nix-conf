{ config, ... }:
let
  network = builtins.fromJSON (builtins.readFile ../../../../hosts/shared/local/network.json);
  domain = network.homelabDomain;
  domainPattern = builtins.replaceStrings [ "." ] [ "\\." ] domain;
  siteUrl = name: "https://${name}.${domain}/";
  siteRoute = name: "^https?://${name}\\.${domainPattern}(?:/|$)";
  homeSpace = "121ff65b-88e8-4ac8-b1cc-3ed7f91ab56d";
  developmentSpace = "5b0dbf3e-f3ee-4534-971f-965d69f503a0";
  mediaSpace = "af22afed-1235-4890-8045-e89da356130b";
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

    # Keep stable everyday spaces and pins. Undeclared pins become ordinary
    # tabs, so the former ChatGPT Essential keeps its open conversation.
    spacesForce = true;
    pinsForce = true;
    pinsForceAction = "demote";

    spaces = {
      Home = {
        id = homeSpace;
        position = 1000;
        icon = "🏠";
        pins.Gmail = {
          id = "c6876424-8f6d-4d60-b252-8940f18e9002";
          url = "https://mail.google.com/mail/u/0/";
          position = 100;
          isEssential = true;
        };
      };

      Development = {
        id = developmentSpace;
        position = 2000;
        icon = "💻";
        pins = {
          "GitHub notifications" = {
            id = "226aa14c-0938-42bc-aa7e-fae2f967a2ed";
            url = "https://github.com/notifications";
            position = 100;
          };
          "nix-conf" = {
            id = "c2cf55d5-93f2-48d0-bce1-b4a8df4c87bb";
            url = "https://github.com/nix-forge/nix-conf";
            position = 200;
          };
        };
        routes = {
          GitHub = {
            matchType = "regex";
            reference = "^https?://github\\.com(?:/|$)";
          };
          NixOS = {
            matchType = "regex";
            reference = "^https?://(?:[a-z0-9-]+\\.)?nixos\\.org(?:/|$)";
          };
          Noogle = {
            matchType = "regex";
            reference = "^https?://noogle\\.dev(?:/|$)";
          };
        };
      };

      Media = {
        id = mediaSpace;
        position = 4000;
        icon = "🎧";
        pins = {
          Seerr = {
            id = "96cc0ed2-ac45-49e2-aa2f-fc7eec2fb937";
            url = siteUrl "seerr";
            position = 100;
          };
          Aurral = {
            id = "645d23b1-c8f3-4781-8808-90930b76ce91";
            url = siteUrl "aurral";
            position = 200;
          };
        };
        routes = {
          Seerr = {
            matchType = "regex";
            reference = siteRoute "seerr";
          };
          Aurral = {
            matchType = "regex";
            reference = siteRoute "aurral";
          };
          Navidrome = {
            matchType = "regex";
            reference = siteRoute "navidrome";
          };
          Jellyfin = {
            matchType = "regex";
            reference = siteRoute "jellyfin";
          };
        };
      };
    };

    spaceRouting = {
      # Drop old Cornell routes, whose destination space no longer exists.
      force = true;
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
        id = "zen-copy-url";
        key = "c";
        modifiers = {
          control = true;
          alt = true;
        };
      }
      {
        id = "zen-compact-mode-toggle";
        key = "m";
        modifiers = {
          control = true;
          alt = true;
        };
      }
    ];
  };
}
