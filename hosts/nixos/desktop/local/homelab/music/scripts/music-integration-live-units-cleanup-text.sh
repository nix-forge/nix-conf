# shellcheck shell=bash
for unit in soularr.service soularr.timer soulseek-directories.service slskd.service aurral.service aurral-bootstrap.service aurral-quality-profile.service aurral-navidrome-host.service aurral-navidrome-vpn.service homelab-integrate-lidarr.service; do
  root="/nix/var/nix/gcroots/music-integration-$unit"
  override="/etc/systemd/system.control/$unit"
  if [[ -L $root && -L $override ]]; then
    store="$(@pkgs_coreutils@/bin/readlink "$root")"
    target="$(@pkgs_coreutils@/bin/readlink "$override")"
    if [[ $target == "$store/$unit" ]]; then
      @pkgs_coreutils@/bin/rm -- "$override" "$root"
    fi
  fi
done
activation=/etc/systemd/system.control/timers.target.d/98-music-integration.conf
if [[ -f $activation && ! -L $activation ]]; then
  IFS= read -r header <"$activation" || true
  if [[ $header == '# Temporary music integration timer activation.' ]]; then
    @pkgs_coreutils@/bin/rm -- "$activation"
  fi
fi
