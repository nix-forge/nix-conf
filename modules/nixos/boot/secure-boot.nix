{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.security.secureBootLanzaboote;
in
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  options.security.secureBootLanzaboote = {
    enable = lib.mkEnableOption ''
      a manually provisioned Lanzaboote Secure Boot chain
    '';

    pkiBundle = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/sbctl";
      description = ''
        Persistent directory containing the Secure Boot signing keys managed
        outside the Nix store. Set this in host-local configuration.
      '';
    };

    configurationLimit = lib.mkOption {
      type = lib.types.ints.between 1 8;
      default = 8;
      description = ''
        Number of signed boot generations retained on the ESP. Eight is the
        maximum supported by systemd-pcrlock and leaves practical headroom on
        small ESPs for UKIs and firmware capsules.
      '';
    };

    bootCountingInitialTries = lib.mkOption {
      type = lib.types.ints.between 1 8;
      default = 3;
      description = ''
        Number of unsuccessful boot attempts before a newly installed entry
        is treated as bad and the loader falls back to an older generation.
      '';
    };

    measuredBoot = {
      enable = lib.mkEnableOption ''
        systemd-pcrlock policy generation for a future LUKS2 TPM2-unlock
        policy
      '';

      pcrs = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            0
            1
            2
            3
            4
            7
          ]
        );
        default = [
          4
          7
        ];
        description = ''
          PCRs represented by the generated policy. PCR 4 covers the measured
          loader/Lanzaboote boot chain, while PCR 7 covers Secure Boot policy.
          Firmware PCRs 0-3 are intentionally not selected by default because
          they make firmware configuration and update recovery more brittle.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Lanzaboote owns systemd-boot installation and writes signed boot
    # artifacts itself. The normal NixOS systemd-boot module must therefore be
    # disabled, while its loader settings remain available to Lanzaboote.
    boot.loader.systemd-boot.enable = lib.mkForce false;

    boot.lanzaboote = {
      enable = true;
      inherit (cfg) pkiBundle;
      inherit (cfg) configurationLimit;

      # A missing or unreadable signing key must fail activation rather than
      # placing an unsigned boot path on the ESP. Key creation and firmware
      # enrollment are intentional, attended recovery-sensitive operations.
      allowUnsigned = false;
      autoGenerateKeys.enable = false;
      autoEnrollKeys = {
        enable = false;
        autoReboot = false;
      };

      # Preserve automatic fallback without presenting a command-line editor
      # that could alter the signed kernel command line.
      bootCounting.initialTries = cfg.bootCountingInitialTries;
      settings.editor = false;

      measuredBoot = {
        enable = cfg.measuredBoot.enable;
        pcrs = cfg.measuredBoot.pcrs;

        # TPM enrollment changes a LUKS2 keyslot and must be performed only
        # after a recovery passphrase and the host's encrypted-root design are
        # tested. It is never an unattended consequence of a boot update.
        autoCryptenroll.enable = false;
      };
    };

    assertions = [
      {
        assertion = cfg.pkiBundle != null;
        message = "security.secureBootLanzaboote requires a host-local persistent pkiBundle outside the Nix store.";
      }
      {
        assertion = config.boot.loader.efi.canTouchEfiVariables;
        message = "security.secureBootLanzaboote requires boot.loader.efi.canTouchEfiVariables so signed loader updates and recovery entries reach UEFI NVRAM.";
      }
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "security.secureBootLanzaboote requires the systemd initrd for the supported measured-boot and future TPM2-unlock path.";
      }
      {
        assertion = config.boot.lanzaboote.allowUnsigned == false;
        message = "security.secureBootLanzaboote must not install unsigned boot artifacts.";
      }
      {
        assertion =
          !config.boot.lanzaboote.autoGenerateKeys.enable && !config.boot.lanzaboote.autoEnrollKeys.enable;
        message = "security.secureBootLanzaboote intentionally requires attended key creation and enrollment; do not automate these recovery-sensitive actions.";
      }
      {
        assertion = !config.boot.lanzaboote.measuredBoot.autoCryptenroll.enable;
        message = "security.secureBootLanzaboote never automatically changes a LUKS2 TPM keyslot; enroll TPM2 only after testing a recovery passphrase.";
      }
      {
        assertion = !cfg.measuredBoot.enable || config.security.tpm2.enable;
        message = "Lanzaboote Measured Boot requires NixOS TPM2 support to be enabled.";
      }
      {
        assertion =
          !cfg.measuredBoot.enable || (lib.elem 4 cfg.measuredBoot.pcrs && lib.elem 7 cfg.measuredBoot.pcrs);
        message = "Measured Boot must cover PCR 4 (boot chain) and PCR 7 (Secure Boot policy).";
      }
      {
        # Preserve the supported NixOS-managed MAC path. Firmware Secure Boot
        # only activates kernel lockdown when the selected kernel was built
        # with that LSM; this module intentionally makes no false promise
        # about that separate kernel-build property.
        assertion = lib.elem "apparmor" config.security.lsm && !lib.elem "selinux" config.security.lsm;
        message = "security.secureBootLanzaboote requires the supported AppArmor LSM path; do not replace it with an unsupported concurrent SELinux configuration.";
      }
      {
        # This desktop uses NVIDIA, USB, networking, and capture drivers that
        # may be loaded after early boot. One-way module locking has a separate
        # compatibility audit and is not a prerequisite for Secure Boot.
        assertion = !config.security.lockKernelModules;
        message = "security.secureBootLanzaboote does not support security.lockKernelModules: make any runtime-module lockdown a separately tested host decision.";
      }
    ];
  };
}
