# shellcheck shell=bash
export WORKSPACE_TOOLS_FILE=@toolPaths@
exec @lib_getExe_tools_python@ -I @runner_py@ @privateConfig@ "$@"
