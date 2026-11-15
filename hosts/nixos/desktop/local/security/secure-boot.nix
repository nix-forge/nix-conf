{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  upstreamLzbt = inputs.lanzaboote.packages.${pkgs.stdenv.hostPlatform.system}.lzbt;
in
{
  # Signed boot generation passed passphrase recovery and firmware Secure Boot
  # enforcement before enabling managed measured boot.
  security.secureBootLanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";

    # Older saved generations still have a USBGuard recovery UKI even though
    # new ones do not. Retain two generations during migration so the booted
    # generation and a new normal one fit alongside both bootloader variants.
    # Raise to four only once the selected four have no specialisations.
    configurationLimit = 2;
    bootCountingInitialTries = 3;

    # pcrlock predicts the signed boot generations in PCR 4. On this MSI
    # firmware it misorders PCR 7 authority and DMA events, so enrollment
    # binds PCR 7's observed value directly and keeps passphrase recovery.
    measuredBoot = {
      enable = true;
      bindPcr7Directly = true;
      pcrs = [ 4 ];
    };
  };

  # Upstream protectedSystem keeps the booted generation within the limit.
  # Require its runtime match to be unique so a missing or duplicated profile
  # cannot silently select the wrong EFI generation.
  boot.lanzaboote.package = pkgs.writeShellApplication {
    name = "lzbt";
    runtimeInputs = [ pkgs.coreutils ];
    text = (import ../../../../../lib/templates/text.nix) ./scripts/lzbt.sh {
      builtins_readFile_lanzaboote_install_guard_sh = builtins.readFile ./lanzaboote-install-guard.sh;
      lib_getExe_upstreamLzbt = lib.getExe upstreamLzbt;
    };
  };

  # systemd-pcrlock can exit successfully after removing every requested PCR.
  # Predict before make-policy so an unrecognized boot image cannot replace a
  # valid policy with an empty one. Keep the postcondition check as well.
  systemd.services.systemd-pcrlock-make-policy.serviceConfig.ExecStartPre = "${pkgs.writeShellScript
    "require-pcr4-prediction"
    (
      (import ../../../../../lib/templates/text.nix) ./scripts/require-pcr4-prediction.sh {
        pkgs_systemd = pkgs.systemd;
        lib_getExe_pkgs_jq = lib.getExe pkgs.jq;
      }
    )
  }";

  systemd.services.systemd-pcrlock-make-policy.serviceConfig.ExecStartPost = "${pkgs.writeShellScript
    "require-pcr4-policy"
    (
      (import ../../../../../lib/templates/text.nix) ./scripts/require-pcr4-policy.sh {
        lib_getExe_pkgs_jq = lib.getExe pkgs.jq;
      }
    )
  }";

  # Available now for preflight, signing-key creation, verification, and
  # recovery diagnostics. Its key bundle stays root-owned at /var/lib/sbctl.
  environment.systemPackages = [ pkgs.sbctl ];
}
