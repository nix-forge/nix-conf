# shellcheck shell=bash
exec @lib_getExe_pkgs_python3@ @recorderSource@ "/run/@name@.json" "$@"
