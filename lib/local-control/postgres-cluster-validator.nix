_:
let
  mkSecureFileSystem =
    pkgs:
    pkgs.stdenv.mkDerivation {
      pname = "local-control-secure-files";
      version = "1";
      src = ./secure-files.c;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      installPhase = ''
        mkdir -p "$out/bin"
        "$CC" -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror \
          "$src" \
          -o "$out/bin/local-control-secure-files"
      '';
    };

  mkEnvironmentSnapshot =
    pkgs:
    let
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.writeShellApplication {
      name = "local-control-environment-snapshot";
      runtimeInputs = [
        pkgs.coreutils
        secureFileSystem
      ];
      text = ''
        set -euo pipefail

        if [ "$#" -ne 3 ] || [ "$1" != read ]; then
          printf 'Usage: local-control-environment-snapshot read ENVIRONMENT_FILE PROXY_MODE\n' >&2
          exit 64
        fi

        environment_file="$2"
        proxy_mode="$3"
        case "$proxy_mode" in
          enabled|disabled)
            ;;
          *)
            printf 'The environment snapshot received an invalid proxy mode.\n' >&2
            exit 64
            ;;
        esac

        required_settings=(
          LOCAL_CONTROL_PROJECT_DIRECTORY
          LOCAL_CONTROL_DATABASE_URL
          LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE
          LOCAL_CONTROL_SCHEMA_COMMAND
          LOCAL_CONTROL_API_COMMAND
          LOCAL_CONTROL_WORKER_COMMAND
          LOCAL_CONTROL_FRONTEND_COMMAND
          LOCAL_CONTROL_PREPARE_COMMAND
          LOCAL_CONTROL_PREPARATION_INPUT
          LOCAL_CONTROL_READINESS_URL
        )
        if [ "$proxy_mode" = enabled ]; then
          required_settings+=(SERVICE_PROXY_ATTESTATION)
        fi

        for required_setting in "''${required_settings[@]}"; do
          unset "$required_setting"
        done
        unset SERVICE_PROXY_ATTESTATION

        environment_snapshot_tmp="$(${pkgs.coreutils}/bin/mktemp)"
        trap '${pkgs.coreutils}/bin/rm -f "$environment_snapshot_tmp"' EXIT
        ${secureFileSystem}/bin/local-control-secure-files read-generation-file \
          "$environment_file" 600 > "$environment_snapshot_tmp"

        environment_seen='|'
        while IFS= read -r environment_line || [ -n "$environment_line" ]; do
          case "$environment_line" in
            ""|\#*)
              continue
              ;;
          esac
          case "$environment_line" in
            *$'\r'*)
              printf 'The environment file contains a carriage return.\n' >&2
              exit 78
              ;;
            *=*)
              environment_name="''${environment_line%%=*}"
              environment_value="''${environment_line#*=}"
              ;;
            *)
              printf 'The environment file must contain only NAME=VALUE records.\n' >&2
              exit 78
              ;;
          esac
          case "$environment_name" in
            LOCAL_CONTROL_PROJECT_DIRECTORY|LOCAL_CONTROL_DATABASE_URL|LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE|LOCAL_CONTROL_SCHEMA_COMMAND|LOCAL_CONTROL_API_COMMAND|LOCAL_CONTROL_WORKER_COMMAND|LOCAL_CONTROL_FRONTEND_COMMAND|LOCAL_CONTROL_PREPARE_COMMAND|LOCAL_CONTROL_PREPARATION_INPUT|LOCAL_CONTROL_READINESS_URL)
              ;;
            SERVICE_PROXY_ATTESTATION)
              if [ "$proxy_mode" != enabled ]; then
                printf 'The environment file contains a proxy setting while the proxy is disabled.\n' >&2
                exit 78
              fi
              ;;
            *)
              printf 'The environment file contains an unsupported setting: %s\n' "$environment_name" >&2
              exit 78
              ;;
          esac
          case "$environment_seen" in
            *"|$environment_name|"*)
              printf 'The environment file contains a duplicate setting: %s\n' "$environment_name" >&2
              exit 78
              ;;
          esac
          environment_seen="''${environment_seen}''${environment_name}|"
          export "$environment_name=$environment_value"
        done < "$environment_snapshot_tmp"

        for required_setting in "''${required_settings[@]}"; do
          if [ -z "''${!required_setting:-}" ]; then
            printf 'The environment file is missing a required setting: %s\n' "$required_setting" >&2
            exit 78
          fi
        done

        ${pkgs.coreutils}/bin/cat "$environment_snapshot_tmp"
      '';
    };

  mkSourceTreeSnapshot =
    pkgs:
    pkgs.writeShellApplication {
      name = "local-control-source-snapshot";
      runtimeInputs = [
        pkgs.coreutils
        (mkSecureFileSystem pkgs)
      ];
      text = ''
        set -euo pipefail
        export LC_ALL=C

        if [ "$#" -ne 1 ]; then
          printf 'Exactly one source directory is required.\n' >&2
          exit 64
        fi
        ${mkSecureFileSystem pkgs}/bin/local-control-secure-files snapshot-tree "$1"
      '';
    };

  mkPreparationProof =
    pkgs:
    let
      environmentSnapshot = mkEnvironmentSnapshot pkgs;
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.writeShellApplication {
      name = "local-control-preparation-proof";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.git
        environmentSnapshot
        secureFileSystem
      ];
      text = ''
                set -euo pipefail
                export LC_ALL=C

                if [ "$#" -ne 4 ] || [ "$1" != compute ]; then
                  printf 'Usage: local-control-preparation-proof compute STATIC_DIGEST PROXY_MODE ENVIRONMENT_FILE\n' >&2
                  exit 64
                fi

                static_configuration_digest="$2"
                proxy_mode="$3"
                environment_file="$4"
                case "$proxy_mode" in
                  enabled|disabled)
                    ;;
                  *)
                    printf 'The preparation proof received an invalid proxy mode.\n' >&2
                    exit 64
                    ;;
                esac

                required_settings=(
                  LOCAL_CONTROL_PROJECT_DIRECTORY
                  LOCAL_CONTROL_DATABASE_URL
                  LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE
                  LOCAL_CONTROL_SCHEMA_COMMAND
                  LOCAL_CONTROL_API_COMMAND
                  LOCAL_CONTROL_WORKER_COMMAND
                  LOCAL_CONTROL_FRONTEND_COMMAND
                  LOCAL_CONTROL_PREPARE_COMMAND
                  LOCAL_CONTROL_PREPARATION_INPUT
                  LOCAL_CONTROL_READINESS_URL
                )
                if [ "$proxy_mode" = enabled ]; then
                  required_settings+=(SERVICE_PROXY_ATTESTATION)
                fi
                for required_setting in "''${required_settings[@]}"; do
                  unset "$required_setting"
                done
                unset SERVICE_PROXY_ATTESTATION

                proof_environment_snapshot="$(${pkgs.coreutils}/bin/mktemp)"
                trap '${pkgs.coreutils}/bin/rm -f "$proof_environment_snapshot"' EXIT
                ${environmentSnapshot}/bin/local-control-environment-snapshot read \
                  "$environment_file" "$proxy_mode" > "$proof_environment_snapshot"

                environment_seen='|'
                while IFS= read -r environment_line || [ -n "$environment_line" ]; do
                  case "$environment_line" in
                    ""|\#*)
                      continue
                      ;;
                    *=*)
                      environment_name="''${environment_line%%=*}"
                      environment_value="''${environment_line#*=}"
                      ;;
                    *)
                      printf 'The environment file must contain only NAME=VALUE records.\n' >&2
                      exit 78
                      ;;
                  esac
                  case "$environment_seen" in
                    *"|$environment_name|"*)
                      printf 'The environment file contains a duplicate setting: %s\n' "$environment_name" >&2
                      exit 78
                      ;;
                  esac
                  environment_seen="''${environment_seen}''${environment_name}|"
                  export "$environment_name=$environment_value"
                done < "$proof_environment_snapshot"

                for required_setting in "''${required_settings[@]}"; do
                  if [ -z "''${!required_setting:-}" ]; then
                    printf 'A required service setting is missing.\n' >&2
                    exit 78
                  fi
                done

                preparation_project_directory="$LOCAL_CONTROL_PROJECT_DIRECTORY"
                # shellcheck disable=SC2016
                source_identity="$(${secureFileSystem}/bin/local-control-secure-files exec-source \
                  "$preparation_project_directory" \
                  ${pkgs.bash}/bin/bash -c ${pkgs.lib.escapeShellArg ''
                    set -euo pipefail
                    # shellcheck disable=SC2016
                    export LC_ALL=C
                    [ -z "$(git -C . rev-parse --show-prefix 2>/dev/null)" ] || {
                      printf 'The preparation source must be the Git checkout root.\n' >&2
                      exit 78
                    }
                    source_revision="$(git -C . rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || {
                      printf 'The Git checkout does not have a known committed revision.\n' >&2
                      exit 78
                    }
                    case "$source_revision" in
                      ""|*[!0-9a-fA-F]*)
                        printf 'The Git revision is not a valid commit identifier.\n' >&2
                        exit 78
                        ;;
                    esac
                    git -C . cat-file -e "$source_revision^{commit}" 2>/dev/null || {
                      printf 'The Git revision could not be verified as a commit.\n' >&2
                      exit 78
                    }
                    source_files_digest="$(${secureFileSystem}/bin/local-control-secure-files snapshot-tree . | \
                      ${pkgs.coreutils}/bin/sha256sum | \
                      ${pkgs.coreutils}/bin/cut -d ' ' -f 1)" || {
                      printf 'The source tree could not be snapshotted safely.\n' >&2
                      exit 78
                    }
                    source_revision_after="$(git -C . rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || {
                      printf 'The Git checkout changed while it was being snapshotted.\n' >&2
                      exit 78
                    }
                    [ "$source_revision" = "$source_revision_after" ] || {
                      printf 'The Git checkout changed while it was being snapshotted.\n' >&2
                      exit 78
                    }
                    printf '%s %s\n' "$source_revision" "$source_files_digest"
                  ''})" || {
                  printf 'The project directory could not be opened as a stable source root.\n' >&2
                  exit 78
                }
                read -r preparation_revision preparation_files_digest <<EOF
        $source_identity
        EOF
                case "$preparation_revision" in
                  ""|*[!0-9a-fA-F]*)
                    printf 'The Git revision was not a deterministic hexadecimal identifier.\n' >&2
                    exit 78
                    ;;
                esac
                case "$preparation_files_digest" in
                  ""|*[!0-9a-fA-F]*)
                    printf 'The source digest was not a deterministic hexadecimal identifier.\n' >&2
                    exit 78
                    ;;
                esac
                case "''${#preparation_revision}" in
                  40|64)
                    ;;
                  *)
                  printf 'The Git revision has an unexpected length.\n' >&2
                  exit 78
                    ;;
                esac
                [ "''${#preparation_files_digest}" -eq 64 ] || {
                  printf 'The source digest has an unexpected length.\n' >&2
                  exit 78
                }

                environment_file_digest="$(${pkgs.coreutils}/bin/sha256sum "$proof_environment_snapshot" | \
                  ${pkgs.coreutils}/bin/cut -d ' ' -f 1)" || {
                  printf 'The environment snapshot could not be hashed safely.\n' >&2
                  exit 78
                }
                preparation_runtime_digest="$({
                  printf 'project-directory\0%s\0' "$preparation_project_directory"
                  printf 'static-configuration-digest\0%s\0' "$static_configuration_digest"
                  printf 'proxy-mode\0%s\0' "$proxy_mode"
                  printf 'environment-file-digest\0%s\0' "$environment_file_digest"
                  for runtime_setting in "''${required_settings[@]}"; do
                    runtime_value="''${!runtime_setting}"
                    runtime_value_digest="$(${pkgs.coreutils}/bin/sha256sum <<<"$runtime_value")"
                    runtime_value_digest="''${runtime_value_digest%% *}"
                    printf '%s\0%s\0' "$runtime_setting" "$runtime_value_digest"
                  done
                  if [ "$proxy_mode" = disabled ]; then
                    printf 'SERVICE_PROXY_ATTESTATION\0disabled\0'
                  fi
                } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)" || {
                  printf 'The launch configuration could not be hashed safely.\n' >&2
                  exit 78
                }

                printf '%s\0%s\0%s\0%s\0%s\0%s' \
                  "$preparation_project_directory" \
                  "$LOCAL_CONTROL_PREPARATION_INPUT" \
                  "$preparation_revision" \
                  "$preparation_files_digest" \
                  "$environment_file_digest" \
                  "$preparation_runtime_digest" |
                  ${pkgs.coreutils}/bin/sha256sum |
                  ${pkgs.coreutils}/bin/cut -d ' ' -f 1
      '';
    };

  mkPrivatePathGuard =
    pkgs:
    let
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.writeShellApplication {
      name = "local-control-private-path";
      runtimeInputs = [ secureFileSystem ];
      text = ''
        set -euo pipefail
        if [ "$#" -lt 2 ]; then
          printf 'Usage: local-control-private-path MODE PATH [DESCRIPTION] [FILE_MODE]\n' >&2
          exit 64
        fi
        case "$1" in
          ensure-directory)
            [ "$#" -ge 3 ] || exit 64
            exec ${secureFileSystem}/bin/local-control-secure-files ensure-directory "$2"
            ;;
          validate-directory)
            [ "$#" -ge 3 ] || exit 64
            exec ${secureFileSystem}/bin/local-control-secure-files validate-directory "$2"
            ;;
          validate-file)
            [ "$#" -eq 4 ] || exit 64
            exec ${secureFileSystem}/bin/local-control-secure-files validate-file "$2" "$4"
            ;;
          *)
            printf 'The private path guard received an invalid mode.\n' >&2
            exit 64
            ;;
        esac
      '';
    };

  mkPreparationGate =
    pkgs:
    let
      environmentSnapshot = mkEnvironmentSnapshot pkgs;
      preparationProof = mkPreparationProof pkgs;
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.writeShellApplication {
      name = "local-control-service-gate";
      runtimeInputs = [
        pkgs.coreutils
        environmentSnapshot
        preparationProof
        secureFileSystem
      ];
      text = ''
        set -euo pipefail
        export LC_ALL=C
        if [ "$#" -lt 6 ]; then
          printf 'Usage: local-control-service-gate ENVIRONMENT_FILE PREPARATION_STAMP STATE_DIRECTORY STATIC_DIGEST PROXY_MODE COMMAND...\n' >&2
          exit 64
        fi
        gate_environment_file="$1"
        gate_preparation_stamp="$2"
        gate_state_directory="$3"
        gate_static_configuration_digest="$4"
        gate_proxy_mode="$5"
        shift 5
        case "$gate_proxy_mode" in
          enabled|disabled)
            ;;
          *)
            printf 'The service gate received an invalid proxy mode.\n' >&2
            exit 64
            ;;
        esac

        gate_environment_snapshot="$(${pkgs.coreutils}/bin/mktemp "$gate_state_directory/gate-environment.XXXXXX")"
        if ! ${environmentSnapshot}/bin/local-control-environment-snapshot read \
          "$gate_environment_file" "$gate_proxy_mode" > "$gate_environment_snapshot"; then
          ${pkgs.coreutils}/bin/rm -f "$gate_environment_snapshot"
          printf 'The service environment is missing, unsafe, or invalid.\n' >&2
          exit 0
        fi

        gate_preparation_state="$(${preparationProof}/bin/local-control-preparation-proof compute \
          "$gate_static_configuration_digest" \
          "$gate_proxy_mode" \
          "$gate_environment_snapshot")" || {
          ${pkgs.coreutils}/bin/rm -f "$gate_environment_snapshot"
          printf 'The service preparation proof is unavailable.\n' >&2
          exit 0
        }
        gate_stamp_value="$(${secureFileSystem}/bin/local-control-secure-files read-file \
          "$gate_preparation_stamp" 600)" || {
          ${pkgs.coreutils}/bin/rm -f "$gate_environment_snapshot"
          printf 'The service preparation stamp is missing or unsafe.\n' >&2
          exit 0
        }
        if [ "$gate_stamp_value" != "$gate_preparation_state" ]; then
          ${pkgs.coreutils}/bin/rm -f "$gate_environment_snapshot"
          printf 'The service preparation stamp is stale.\n' >&2
          exit 0
        fi

        export LOCAL_CONTROL_ENVIRONMENT_SNAPSHOT="$gate_environment_snapshot"
        exec "$@"
      '';
    };

  mkDatabaseClusterValidator =
    pkgs:
    let
      secureFileSystem = mkSecureFileSystem pkgs;
    in
    pkgs.writeShellApplication {
      name = "local-control-validate-database-cluster";
      runtimeInputs = [
        pkgs.postgresql_18
        secureFileSystem
      ];
      text = ''
        set -euo pipefail
        if [ "$#" -ne 1 ]; then
          printf 'Exactly one database directory is required.\n' >&2
          exit 64
        fi
        ${secureFileSystem}/bin/local-control-secure-files exec-cluster \
          "$1" 18 ${pkgs.postgresql_18}/bin/pg_controldata . >/dev/null 2>&1
      '';
    };
in
{
  inherit
    mkEnvironmentSnapshot
    mkPreparationGate
    mkPreparationProof
    mkPrivatePathGuard
    mkSecureFileSystem
    mkSourceTreeSnapshot
    mkDatabaseClusterValidator
    ;
}
