{
  config,
  lib,
  myLib,
  pkgs,
  utils,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  cfg = config.hardware.storage.encryptedRoot;
  inherit (import ./.storage-roles.nix)
    bulkLockPath
    dataMount
    gamesMount
    runtimeDirectory
    vmImagesMount
    workMount
    ;
  homeUsers = lib.filterAttrs (
    name: user: (user.isNormalUser or false) && user.home == "/home/${name}"
  ) config.users.users;
  homeSubvolumes = lib.concatLists (
    lib.mapAttrsToList (
      name: user:
      let
        group = if user.group == null then "users" else user.group;
        rule = path: "v /home/${name}/${path} 0700 ${name} ${group} - -";
      in
      [
        "d /home/${name}/.local 0700 ${name} ${group} - -"
        "d /home/${name}/.local/share 0700 ${name} ${group} - -"
        (rule ".cache")
        (rule ".local/share/docker")
      ]
    ) homeUsers
  );
  runtime =
    (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).desktopStorageRuntime;
  enrollmentPolicy = (pkgs.formats.json { }).generate "desktop-storage-enrollment.json" {
    secureBootCheck = lib.getExe' runtime "desktop-storage-check-secure-boot";
    inherit (cfg) dataKeyFile;
    inherit (cfg) homelabKeyFile;
    measuredBoot = config.security.secureBootLanzaboote.measuredBoot.enable or false;
    pcrlockPolicy =
      config.boot.lanzaboote.measuredBoot.pcrlockPolicy or "/var/lib/systemd/pcrlock.json";
    pcrlockExecutable = "${config.systemd.package}/lib/systemd/systemd-pcrlock";
  };
  enrollment = writeShellApplication {
    name = "desktop-storage-enroll";
    runtimeInputs = [
      pkgs.cryptsetup
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec ${lib.getExe' runtime "desktop-storage-enroll"} ${enrollmentPolicy} "$@"
    '';
  };
  mounts = [
    dataMount
    workMount
    gamesMount
    vmImagesMount
  ];
  snapshot = path: {
    SUBVOLUME = path;
    FSTYPE = "btrfs";
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    # Ranges permit a second cleanup pass under space pressure. FREE_LIMIT
    # uses filesystem free space and does not require Btrfs quota accounting.
    TIMELINE_LIMIT_HOURLY = "2-24";
    TIMELINE_LIMIT_DAILY = "1-7";
    TIMELINE_LIMIT_WEEKLY = "1-4";
    FREE_LIMIT = 0.2;
    TIMELINE_LIMIT_MONTHLY = 0;
    TIMELINE_LIMIT_YEARLY = 0;
    EMPTY_PRE_POST_CLEANUP = true;
  };
in
{
  imports = [
    ./backups.nix
    ./health.nix
  ];

  options.hardware.storage.encryptedRoot = {
    enable = lib.mkEnableOption "the offline-provisioned two-drive encrypted desktop layout";
    dataKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/desktop-storage/keys/data.key";
      description = "Private runtime keyfile enrolled into cryptdata, stored only on encrypted root.";
    };
    homelabKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/desktop-storage/keys/homelab.key";
      description = "Private keyfile enrolled into the optional homelab HDD after encrypted-root migration.";
    };
    unlockMethod = lib.mkOption {
      type = lib.types.enum [
        "passphrase"
        "tpm-pin"
        "fido2"
      ];
      default = "passphrase";
      description = "Boot unlock path selected after testing recovery and enrolling credentials at the console.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ enrollment ];
        system.build.desktopStorageEnroll = enrollment;
        # The legacy switch was removed when systemd became the only initrd.
        boot.initrd.systemd =
          lib.optionalAttrs (lib.versionOlder (lib.versions.majorMinor lib.version) "26.11")
            { enable = true; };
        boot.initrd.availableKernelModules = [
          "usbhid"
          "hid_generic"
          "xhci_pci"
        ];
        boot.initrd.luks.devices.cryptroot.crypttabExtraOpts =
          lib.optionals (cfg.unlockMethod == "tpm-pin") [ "tpm2-device=auto" ]
          ++ lib.optionals (cfg.unlockMethod == "fido2") [
            "fido2-device=auto"
            "token-timeout=15s"
          ];
        # Explicitly retain passphrase fallback. Enrollment determines PIN/touch
        # policy; a crypttab option cannot retrofit a PIN onto an existing token.
        environment.etc."crypttab".text = ''
          cryptdata /dev/disk/by-partlabel/NIXOS-CRYPTDATA ${cfg.dataKeyFile} luks,nofail,headless,discard,keyfile-timeout=10s,x-systemd.device-timeout=10s
        '';
        boot.resumeDevice = lib.mkForce "";
        systemd.sleep.settings.Sleep = {
          AllowHibernation = "no";
          AllowHybridSleep = "no";
          AllowSuspendThenHibernate = "no";
        };

        systemd.tmpfiles.rules = [
          "d ${runtimeDirectory} 0700 root root - -"
          "f ${bulkLockPath} 0600 root root - -"
          "d /var/lib/desktop-storage/keys 0700 root root - -"
          "d /var/lib/desktop-storage/recovery 0700 root root - -"
          "z /home/.snapshots 0700 root root - -"
        ]
        ++ homeSubvolumes;

        # tmpfiles does not replace an existing directory with a subvolume.
        # Refuse logins and home snapshots if a restore crossed that boundary.
        systemd.services.desktop-home-subvolumes = {
          description = "Verify per-user home snapshot exclusions";
          requiredBy = [ "systemd-user-sessions.service" ];
          before = [ "systemd-user-sessions.service" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          unitConfig.RequiresMountsFor = [ "/home" ];
          serviceConfig = {
            Type = "oneshot";
            StandardOutput = "null";
            ExecStart = map utils.escapeSystemdExecArgs (
              if homeUsers == { } then
                [ [ (lib.getExe' pkgs.coreutils "true") ] ]
              else
                lib.concatMap (name: [
                  [
                    (lib.getExe' pkgs.btrfs-progs "btrfs")
                    "subvolume"
                    "show"
                    "/home/${name}/.cache"
                  ]
                  [
                    (lib.getExe' pkgs.btrfs-progs "btrfs")
                    "subvolume"
                    "show"
                    "/home/${name}/.local/share/docker"
                  ]
                ]) (builtins.attrNames homeUsers)
            );
          };
        };
        systemd.services."user@" = {
          requires = [ "desktop-home-subvolumes.service" ];
          after = [ "desktop-home-subvolumes.service" ];
        };
        systemd.services.desktop-snapshot-home-timeline = {
          requires = [ "desktop-home-subvolumes.service" ];
          after = [ "desktop-home-subvolumes.service" ];
        };
        systemd.services.desktop-snapshot-home-cleanup = {
          requires = [ "desktop-home-subvolumes.service" ];
          after = [ "desktop-home-subvolumes.service" ];
        };

        # The optional data drive must not block login, but services must never
        # write replacement data into its unmounted directories on the system SSD.
        systemd.services.desktop-data-ready = {
          description = "Prepare mounted desktop data directories";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = mounts;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = map utils.escapeSystemdExecArgs (
              map (path: [
                (lib.getExe' pkgs.util-linux "mountpoint")
                "-q"
                path
              ]) mounts
              ++ [
                [
                  (lib.getExe' pkgs.coreutils "chmod")
                  "0700"
                  "${dataMount}/.snapshots"
                  "${workMount}/.snapshots"
                ]
                # Clear inherited NOCOW after restores. Existing extents need a
                # separate cold copy to regain data checksums.
                [
                  (lib.getExe' pkgs.e2fsprogs "chattr")
                  "-C"
                  vmImagesMount
                ]
                # Steam checks access at the library root. Change ownership
                # only after verifying that all data mounts are present.
                [
                  (lib.getExe' pkgs.coreutils "chown")
                  "root:users"
                  gamesMount
                ]
                [
                  (lib.getExe' pkgs.coreutils "chmod")
                  "2775"
                  gamesMount
                ]
                [
                  (lib.getExe' pkgs.coreutils "install")
                  "-d"
                  "-m"
                  "2775"
                  "-o"
                  "root"
                  "-g"
                  "users"
                  "${gamesMount}/steamapps"
                  "${workMount}/projects"
                  "${dataMount}/media"
                ]
              ]
            );
          };
        };
        # The pre-start check also covers nofail mounts, whose dependency
        # strength differs by systemd.
        systemd.services.libvirtd = lib.mkIf config.virtualisation.libvirtd.enable {
          requires = [ "desktop-data-ready.service" ];
          after = [ "desktop-data-ready.service" ];
          unitConfig.RequiresMountsFor = [ vmImagesMount ];
          serviceConfig.ExecStartPre = [ "${pkgs.util-linux}/bin/mountpoint -q ${vmImagesMount}" ];
        };
        # A restored pool can autostart with its old NOCOW policy before the
        # reconciler updates its persistent XML. Repair directory inheritance
        # again after reconciliation, without restarting an active pool.
        systemd.services.libvirt-workstation-setup =
          lib.mkIf (config.virtualisation.libvirtWorkstation.enable or false)
            {
              serviceConfig.ExecStartPost = [
                "${pkgs.util-linux}/bin/mountpoint -q ${vmImagesMount}"
                "${pkgs.e2fsprogs}/bin/chattr -C ${vmImagesMount}"
              ];
            };

        services.snapper = {
          snapshotRootOnBoot = false;
          snapshotInterval = "hourly";
          persistentTimer = true;
          configs = {
            home = snapshot "/home";
            data = snapshot dataMount;
            work = snapshot workMount;
          };
        };
        # Run each filesystem independently. Upstream's shared jobs couple all
        # configs, so an absent optional SSD would also prevent home retention.
        systemd.services.snapper-timeline.enable = false;
        systemd.services.snapper-cleanup.enable = false;
        systemd.timers.snapper-timeline.enable = false;
        systemd.timers.snapper-cleanup.enable = false;

        assertions = [
          {
            assertion = lib.hasPrefix "/" cfg.dataKeyFile && !lib.hasPrefix "/nix/store/" cfg.dataKeyFile;
            message = "cryptdata requires a private absolute runtime keyfile outside the Nix store.";
          }
          {
            assertion = lib.hasPrefix "/" cfg.homelabKeyFile && !lib.hasPrefix "/nix/store/" cfg.homelabKeyFile;
            message = "The homelab HDD requires a private absolute keyfile outside the Nix store.";
          }
          {
            assertion =
              cfg.unlockMethod != "tpm-pin"
              || (
                config.security.tpm2.enable
                && config.security.secureBootLanzaboote.enable
                && config.security.secureBootLanzaboote.measuredBoot.enable
              );
            message = "TPM-PIN unlock requires the tested TPM2, Secure Boot and managed measured-boot configuration.";
          }
          {
            assertion = cfg.unlockMethod != "fido2" || config.security.secureBootLanzaboote.enable;
            message = "Enable the tested signed boot chain before selecting FIDO2 boot unlocking.";
          }
        ];
      }
      {
        systemd.services = lib.listToAttrs (
          lib.concatMap
            (
              name:
              let
                path = config.services.snapper.configs.${name}.SUBVOLUME;
              in
              map
                (
                  phase:
                  lib.nameValuePair "desktop-snapshot-${name}-${phase}" {
                    description = "Snapper ${phase} for ${name}";
                    unitConfig = {
                      RequiresMountsFor = [ path ];
                      ConditionPathIsMountPoint = path;
                    };
                    serviceConfig = {
                      Type = "oneshot";
                      ExecStartPre = "${pkgs.coreutils}/bin/chmod 0700 ${path}/.snapshots";
                      ExecCondition = lib.mkIf (
                        cfg.capacity.enable && phase == "timeline"
                      ) "${lib.getExe config.system.build.desktopStorageCapacity} snapshot ${lib.escapeShellArg path}";
                      ExecStart =
                        let
                          snapper =
                            args:
                            utils.escapeSystemdExecArgs (
                              [
                                (lib.getExe' pkgs.snapper "snapper")
                                "--config"
                                name
                              ]
                              ++ args
                            );
                        in
                        if phase == "timeline" then
                          snapper [
                            "create"
                            "--type"
                            "single"
                            "--cleanup-algorithm"
                            "timeline"
                            "--description"
                            "timeline"
                          ]
                        else
                          [
                            (snapper [
                              "cleanup"
                              "timeline"
                            ])
                            (snapper [
                              "cleanup"
                              "empty-pre-post"
                            ])
                          ];
                    };
                  }
                )
                [
                  "timeline"
                  "cleanup"
                ]
            )
            [
              "home"
              "data"
              "work"
            ]
        );
        systemd.timers = lib.listToAttrs (
          lib.concatMap
            (
              name:
              map
                (
                  phase:
                  lib.nameValuePair "desktop-snapshot-${name}-${phase}" {
                    wantedBy = [ "timers.target" ];
                    timerConfig = {
                      OnCalendar = "hourly";
                      Persistent = true;
                      RandomizedDelaySec = "5m";
                    };
                  }
                )
                [
                  "timeline"
                  "cleanup"
                ]
            )
            [
              "home"
              "data"
              "work"
            ]
        );
      }
    ]
  );
}
