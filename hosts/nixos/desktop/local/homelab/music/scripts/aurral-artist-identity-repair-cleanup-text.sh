# shellcheck shell=bash
aurral_repair_override=/etc/systemd/system.control/aurral.service.d/96-artist-identity.conf
if [[ -f $aurral_repair_override && ! -L $aurral_repair_override ]]; then
  IFS= read -r aurral_repair_header <"$aurral_repair_override" || true
  if [[ $aurral_repair_header == '# Temporary Aurral artist identity repair.' ]]; then
    @pkgs_coreutils@/bin/rm -- "$aurral_repair_override"
  fi
fi
