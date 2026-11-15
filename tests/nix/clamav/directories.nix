{ pkgs }:
let
  inherit (pkgs) lib;
  evaluate =
    homeUsers: overrides:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../../../modules/nixos/security/clamav.nix
        ../../../hosts/nixos/desktop/local/security/clamav.nix
        ({ lib, ... }: {
          options.home-manager.users = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          config = {
            system.stateVersion = "23.11";
            users.users.alex = {
              isNormalUser = true;
              home = "/srv/accounts/alex";
            };
            home-manager.users = homeUsers;
            services.clamav.daemon.settings = overrides;
          };
        })
      ];
    }).config;
  selected = {
    alex.xdg.userDirs = {
      enable = true;
      download = "/srv/incoming/alex";
      desktop = "/srv/workspaces/alex";
    };
  };
  paths = config: config.services.clamav.daemon.settings.OnAccessIncludePath;
  valid =
    config:
    !(lib.any (
      entry: !entry.assertion && lib.hasPrefix "ClamAV on-access scanning requires" entry.message
    ) config.assertions);
  ordinary = evaluate { } { };
  relocated = evaluate selected { };
  nullable = evaluate {
    alex.xdg.userDirs = selected.alex.xdg.userDirs // {
      desktop = null;
    };
  } { };
  disabled = evaluate {
    alex.xdg.userDirs = selected.alex.xdg.userDirs // {
      enable = false;
    };
  } { };
  explicit = evaluate selected { OnAccessIncludePath = [ "/srv/explicit" ]; };
  empty = evaluate {
    alex.xdg.userDirs = {
      enable = true;
      download = null;
      desktop = null;
    };
  } { };
  relative = evaluate selected { OnAccessIncludePath = [ "relative/path" ]; };
in
assert
  paths ordinary == [
    "/srv/accounts/alex/Downloads"
    "/srv/accounts/alex/Desktop"
  ];
assert
  paths relocated == [
    "/srv/incoming/alex"
    "/srv/workspaces/alex"
  ];
assert paths nullable == [ "/srv/incoming/alex" ];
assert paths disabled == paths ordinary;
assert paths explicit == [ "/srv/explicit" ];
assert lib.all valid [
  ordinary
  relocated
  nullable
  disabled
  explicit
];
assert !(valid empty);
assert !(valid relative);
(pkgs.formats.json { }).generate "clamav-selected-user-directories.json" {
  ordinary = paths ordinary;
  relocated = paths relocated;
  nullable = paths nullable;
  explicit = paths explicit;
  emptyRejected = !(valid empty);
  relativeRejected = !(valid relative);
}
