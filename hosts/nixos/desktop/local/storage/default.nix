{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.storage.encryptedRoot;
  enrollment = pkgs.writeShellApplication {
    name = "desktop-storage-enroll";
    runtimeInputs = [
      pkgs.cryptsetup
      pkgs.systemd
      pkgs.coreutils
      pkgs.util-linux
      pkgs.jq
      pkgs.python3
    ];
    text =
      builtins.replaceStrings
        [ "@dataKeyFile@" "@measuredBoot@" "@pcrlockPolicy@" "@pcrlockExecutable@" ]
        [
          (lib.escapeShellArg cfg.dataKeyFile)
          (lib.boolToString (config.security.secureBootLanzaboote.measuredBoot.enable or false))
          (lib.escapeShellArg (
            config.boot.lanzaboote.measuredBoot.pcrlockPolicy or "/var/lib/systemd/pcrlock.json"
          ))
          (lib.escapeShellArg "${config.systemd.package}/lib/systemd/systemd-pcrlock")
        ]
        (builtins.readFile ./enroll.sh);
  };
  mounts = [
    "/srv/data"
    "/srv/data/work"
    "/mnt/games"
    "/var/lib/libvirt/images"
  ];
  snapshot = path: {
    SUBVOLUME = path;
    FSTYPE = "btrfs";
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    # Ranges permit a second cleanup pass under space pressure. FREE_LIMIT
    # uses filesystem free space and does not require Btrfs quota accounting.
    TIMELINE_LIMIT_HOURLY = "0-24";
    TIMELINE_LIMIT_DAILY = "0-7";
    TIMELINE_LIMIT_WEEKLY = "0-4";
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
        boot.initrd.systemd.enable = true;
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
          "d /var/lib/desktop-storage/keys 0700 root root - -"
          "d /var/lib/desktop-storage/recovery 0700 root root - -"
          "d /home/ianmh 0700 ianmh users - -"
          "d /home/ianmh/.cache 0700 ianmh users - -"
          "z /home/.snapshots 0700 root root - -"
          "d /home/ianmh/.local 0700 ianmh users - -"
          "d /home/ianmh/.local/share 0700 ianmh users - -"
          "d /home/ianmh/.local/share/docker 0700 ianmh users - -"
        ];

        # The optional data drive must not block login, but services must never
        # write replacement data into its unmounted directories on the system SSD.
        systemd.services.desktop-data-ready = {
          description = "Prepare mounted desktop data directories";
          wantedBy = [ "multi-user.target" ];
          unitConfig.RequiresMountsFor = mounts;
          path = [
            pkgs.util-linux
            pkgs.coreutils
            pkgs.e2fsprogs
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -eu
            ${lib.concatMapStringsSep "\n" (path: "mountpoint -q ${lib.escapeShellArg path}") mounts}
            chmod 0700 /srv/data/.snapshots /srv/data/work/.snapshots
            # Clear inherited directory NOCOW after a restore. Existing image
            # extents need a separate cold copy to regain data checksums.
            chattr -C /var/lib/libvirt/images
            install -d -m 2775 -o root -g users /mnt/games/steamapps /srv/data/work/projects /srv/data/media
          '';
        };
        # The pre-start check also covers nofail mounts, whose dependency
        # strength differs by systemd.
        systemd.services.libvirtd = lib.mkIf config.virtualisation.libvirtd.enable {
          requires = [ "desktop-data-ready.service" ];
          after = [ "desktop-data-ready.service" ];
          unitConfig.RequiresMountsFor = [ "/var/lib/libvirt/images" ];
          serviceConfig.ExecStartPre = [ "${pkgs.util-linux}/bin/mountpoint -q /var/lib/libvirt/images" ];
        };
        # A restored pool can autostart with its old NOCOW policy before the
        # reconciler updates its persistent XML. Repair directory inheritance
        # again after reconciliation, without restarting an active pool.
        systemd.services.libvirt-workstation-setup =
          lib.mkIf (config.virtualisation.libvirtWorkstation.enable or false)
            {
              serviceConfig.ExecStartPost = [
                "${pkgs.util-linux}/bin/mountpoint -q /var/lib/libvirt/images"
                "${pkgs.e2fsprogs}/bin/chattr -C /var/lib/libvirt/images"
              ];
            };

        services.snapper = {
          snapshotRootOnBoot = false;
          snapshotInterval = "hourly";
          persistentTimer = true;
          configs = {
            home = snapshot "/home";
            data = snapshot "/srv/data";
            work = snapshot "/srv/data/work";
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
                    serviceConfig.Type = "oneshot";
                    serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/chmod 0700 ${path}/.snapshots";
                    script =
                      if phase == "timeline" then
                        ''
                          ${pkgs.snapper}/bin/snapper --config ${name} create --type single --cleanup-algorithm timeline --description timeline
                        ''
                      else
                        ''
                          ${pkgs.snapper}/bin/snapper --config ${name} cleanup timeline
                          ${pkgs.snapper}/bin/snapper --config ${name} cleanup empty-pre-post
                        '';
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
