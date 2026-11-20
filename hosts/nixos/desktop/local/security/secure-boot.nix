{
  inputs,
  lib,
  myLib,
  pkgs,
  ...
}:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  writeShellScript = myLib.writers.writeShellScript { inherit pkgs; };
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
  boot.lanzaboote.package = writeShellApplication {
    name = "lzbt";
    text = ''
      exec ${
        lib.getExe'
          (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).desktopStorageRuntime
          "desktop-guard-boot-install"
      } ${lib.getExe upstreamLzbt} "$@"
    '';
  };

  # systemd-pcrlock can exit successfully after removing every requested PCR.
  # Predict before make-policy so an unrecognized boot image cannot replace a
  # valid policy with an empty one. Keep the postcondition check as well.
  systemd.services.systemd-pcrlock-make-policy.serviceConfig.ExecStartPre = "${writeShellScript
    "require-pcr4-prediction"
    (
      myLib.templates.renderText
        {
          name = "require-pcr4-prediction.sh";
          text = ''
            # shellcheck shell=bash
            prediction="$(@pkgs_systemd@/lib/systemd/systemd-pcrlock predict --json=short --components=/etc/pcrlock.d --components=/var/lib/pcrlock.d --location=770 --pcr=4)" || exit 1
            if ! @lib_getExe_pkgs_jq@ -e 'type == "object" and length > 0' <<<"$prediction" >/dev/null; then
              echo 'systemd-pcrlock cannot predict PCR 4; refusing to replace the policy' >&2
              exit 1
            fi
          '';
        }
        {
          pkgs_systemd = pkgs.systemd;
          lib_getExe_pkgs_jq = lib.getExe pkgs.jq;
        }
    )
  }";

  systemd.services.systemd-pcrlock-make-policy.serviceConfig.ExecStartPost = "${writeShellScript
    "require-pcr4-policy"
    (
      myLib.templates.renderText
        {
          name = "require-pcr4-policy.sh";
          text = ''
            # shellcheck shell=bash
            if ! @lib_getExe_pkgs_jq@ -e 'any(.pcrValues[]?; .pcr == 4)' /var/lib/systemd/pcrlock.json >/dev/null; then
              echo 'systemd-pcrlock generated a policy without PCR 4' >&2
              exit 1
            fi
          '';
        }
        {
          lib_getExe_pkgs_jq = lib.getExe pkgs.jq;
        }
    )
  }";

  # Available now for preflight, signing-key creation, verification, and
  # recovery diagnostics. Its key bundle stays root-owned at /var/lib/sbctl.
  environment.systemPackages = [ pkgs.sbctl ];
}
