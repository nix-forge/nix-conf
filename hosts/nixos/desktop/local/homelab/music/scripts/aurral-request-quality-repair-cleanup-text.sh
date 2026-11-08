# shellcheck shell=bash
repair=/etc/systemd/system.control/aurral-bootstrap.service.d/97-request-quality.conf
if [[ -f $repair && ! -L $repair ]]; then
  IFS= read -r header <"$repair" || true
  if [[ $header == '# Temporary Aurral request quality repair.' ]]; then
    @pkgs_coreutils@/bin/rm -- "$repair"
    @pkgs_coreutils@/bin/rm -f -- /nix/var/nix/gcroots/aurral-request-quality-repair
  fi
fi
