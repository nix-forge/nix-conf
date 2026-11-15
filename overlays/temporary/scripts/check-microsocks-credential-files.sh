# shellcheck shell=bash
runHook preCheck
python3 @tests_microsocks_credential_files_py@ ./microsocks
runHook postCheck
