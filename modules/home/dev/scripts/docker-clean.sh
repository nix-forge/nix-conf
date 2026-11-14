# shellcheck shell=bash
case "${1-}" in
"")
  @lib_getExe_pkgs_docker@ system df
  printf '%s\n' 'Pass --images to prune unused images and build cache, or --volumes to include unused volumes.'
  ;;
--images)
  exec @lib_getExe_pkgs_docker@ system prune --all --force
  ;;
--volumes)
  exec @lib_getExe_pkgs_docker@ system prune --all --volumes --force
  ;;
*)
  printf '%s\n' 'usage: docker-clean [--images|--volumes]' >&2
  exit 64
  ;;
esac
