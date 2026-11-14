# shellcheck shell=bash
if @lib_getExe_pkgs_systemd_systemctl@ --user is-active --quiet docker.service; then
  mapfile -t container_ids < <(@lib_getExe_pkgs_docker@ container ls --quiet)
  if [ "${#container_ids[@]}" -gt 0 ]; then
    @lib_getExe_pkgs_docker@ container stop "${container_ids[@]}"
  fi
  @lib_getExe_pkgs_systemd_systemctl@ --user stop docker.service
else
  printf '%s\n' 'Docker is already stopped.'
fi
