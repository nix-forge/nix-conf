# Exercise the real module with ordinary and ordered caller additions.
{ lib }:
let
  evaluate =
    additions:
    (lib.evalModules {
      specialArgs.pkgs = { };
      modules = [
        ../../hosts/nixos/desktop/local/storage/backups.nix
        {
          options = {
            hardware.storage.encryptedRoot.enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            users.users = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            services.restic.backups = lib.mkOption { type = lib.types.attrs; };
            system.activationScripts = lib.mkOption { type = lib.types.attrs; };
            systemd.services = lib.mkOption { type = lib.types.attrs; };
            systemd.timers = lib.mkOption { type = lib.types.attrs; };
            environment.systemPackages = lib.mkOption { type = lib.types.listOf lib.types.raw; };
            environment.etc = lib.mkOption { type = lib.types.attrs; };
            system.build.desktopBackupCheck = lib.mkOption { type = lib.types.raw; };
            assertions = lib.mkOption { type = lib.types.listOf lib.types.raw; };
          };
          config = {
            hardware.storage.encryptedRoot.backup.exclude = additions;
          };
        }
      ];
    }).config.hardware.storage.encryptedRoot.backup.exclude;
  required = [
    "**/.snapshots"
    "/home/*/.cache"
    "/var/lib/docker"
    "/var/lib/libvirt"
  ];
  preserved =
    additions:
    let
      result = evaluate additions;
    in
    lib.all (item: lib.elem item result) (required ++ [ "/fixture-extra" ]);
in
assert preserved [ "/fixture-extra" ];
assert preserved (lib.mkAfter [ "/fixture-extra" ]);
assert preserved (lib.mkBefore [ "/fixture-extra" ]);
true
