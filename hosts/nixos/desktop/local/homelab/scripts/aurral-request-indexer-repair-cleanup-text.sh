# shellcheck shell=bash
repair=/etc/systemd/system.control/prowlarr.service.d/97-aurral-requests.conf
if [[ -f $repair && ! -L $repair ]]; then
  IFS= read -r header <"$repair" || true
  if [[ $header == '# Temporary Aurral request indexer repair.' ]]; then
    @pkgs_coreutils@/bin/rm -- "$repair"
    @pkgs_coreutils@/bin/rm -f -- /nix/var/nix/gcroots/aurral-request-indexer-repair
  fi
fi
