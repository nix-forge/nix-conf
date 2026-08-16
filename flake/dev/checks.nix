{ inputs, ... }: {
  perSystem =
    { pkgs, ... }:
    let
      localControlLibrary = import ../../lib/local-control/postgres-cluster-validator.nix { };
      secureFileSystem = localControlLibrary.mkSecureFileSystem pkgs;
      environmentSnapshot = localControlLibrary.mkEnvironmentSnapshot pkgs;
      sourceTreeSnapshot = localControlLibrary.mkSourceTreeSnapshot pkgs;
      databaseClusterValidator = localControlLibrary.mkDatabaseClusterValidator pkgs;
      preparationProof = localControlLibrary.mkPreparationProof pkgs;
      preparationGate = localControlLibrary.mkPreparationGate pkgs;
      privatePathGuard = localControlLibrary.mkPrivatePathGuard pkgs;
      localControlProxyConfig = pkgs.writeText "local-control-proxy-check.conf" (
        (import ../../lib/local-control/proxy-config.nix { }).mkProxyConfig {
          bindAddress = "127.0.0.1";
          dashboardDirectory = "/tmp/local-control/dashboard-current";
          webPort = 15173;
          apiPort = 18788;
          proxyPort = 18443;
        }
      );
    in
    {
      checks.dev-vm-host-resolution =
        pkgs.runCommand "dev-vm-host-resolution" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            export DEV_VM_HOST_MODULE=${../../homes/macbook-pro-m4/local/dev_vm_host.py}
            ${pkgs.python3}/bin/python3 ${../../homes/macbook-pro-m4/local/dev_vm_host_test.py}
            touch "$out"
          '';

      checks.local-control-proxy-tls-policy =
        pkgs.runCommand "local-control-proxy-tls-policy"
          {
            nativeBuildInputs = [
              pkgs.caddy
              pkgs.jq
            ];
          }
          ''
            set -euo pipefail

            export LOCAL_CONTROL_PROXY_CERT=/runtime/server.crt
            export LOCAL_CONTROL_PROXY_KEY=/runtime/server.key
            export LOCAL_CONTROL_PROXY_CA=/runtime/ca.crt
            export SERVICE_PROXY_ATTESTATION=fixture-private-attestation
            caddy adapt \
              --config ${localControlProxyConfig} \
              --adapter caddyfile \
              > adapted.json

            private_server="$(${pkgs.jq}/bin/jq -c '
              [.apps.http.servers[] | select(.listen == ["127.0.0.1:18443"])]
            ' adapted.json)"
            [ "$private_server" != '[]' ]
            [ "$(${pkgs.jq}/bin/jq 'length' <<< "$private_server")" -eq 1 ]

            # The policy must apply to every connection on the host-only bound
            # listener. An SNI matcher would bypass mTLS for IP-address clients.
            ${pkgs.jq}/bin/jq -e '
              .[0].tls_connection_policies
              | length == 1
                and (.[0] | has("match") | not)
                and .[0].client_authentication.mode == "require_and_verify"
                and .[0].client_authentication.ca.provider == "file"
            ' <<< "$private_server" >/dev/null

            ${pkgs.jq}/bin/jq -e '
              [.[0].routes[]?.handle[]?.routes[]?.handle[]?
                | select(.handler == "reverse_proxy")
                | .headers.request.set["X-Client-Certificate-Fingerprint"][]?]
              | any(. == "{http.request.tls.client.fingerprint}")
            ' <<< "$private_server" >/dev/null

            touch "$out"
          '';

      checks.local-control-database-validation =
        pkgs.runCommand "local-control-database-validation" { }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-database-validation"
            existing_cluster="$test_root/existing"
            new_cluster="$test_root/new"
            ${pkgs.coreutils}/bin/mkdir -p "$existing_cluster" "$new_cluster"

            ${pkgs.postgresql_18}/bin/initdb \
              --pgdata="$existing_cluster" \
              --auth-local=trust \
              --auth-host=scram-sha-256 \
              --encoding=UTF8 \
              --no-locale >/dev/null
            ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$existing_cluster"

            linked_cluster="$test_root/linked"
            ${pkgs.coreutils}/bin/ln -s "$existing_cluster" "$linked_cluster"
            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$linked_cluster"; then
              printf 'A symlinked database directory was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/chmod 755 "$existing_cluster"
            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$existing_cluster"; then
              printf 'A group-readable database directory was accepted.\n' >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/chmod 700 "$existing_cluster"

            ${pkgs.coreutils}/bin/chmod 644 "$existing_cluster/postgresql.conf"
            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$existing_cluster"; then
              printf 'A group-readable database control file was accepted.\n' >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/chmod 600 "$existing_cluster/postgresql.conf"

            corrupt_cluster="$test_root/corrupt"
            ${pkgs.coreutils}/bin/mkdir -p "$corrupt_cluster"
            ${pkgs.postgresql_18}/bin/initdb \
              --pgdata="$corrupt_cluster" \
              --auth-local=trust \
              --auth-host=scram-sha-256 \
              --encoding=UTF8 \
              --no-locale >/dev/null
            ${pkgs.coreutils}/bin/printf '17\n' > "$corrupt_cluster/PG_VERSION"
            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$corrupt_cluster"; then
              printf 'An incompatible database marker was accepted.\n' >&2
              exit 1
            fi

            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$new_cluster"; then
              printf 'An uninitialized database directory was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.postgresql_18}/bin/initdb \
              --pgdata="$new_cluster" \
              --auth-local=trust \
              --auth-host=scram-sha-256 \
              --encoding=UTF8 \
              --no-locale >/dev/null
            ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${databaseClusterValidator}/bin/local-control-validate-database-cluster "$new_cluster"

            socket_directory="$test_root/socket"
            postgres_log="$test_root/postgres.log"
            ${pkgs.coreutils}/bin/mkdir -m 700 "$socket_directory"
            postgres_pid=""
            stop_postgres() {
              if [ -n "$postgres_pid" ]; then
                kill -TERM "$postgres_pid" 2>/dev/null || true
                wait "$postgres_pid" 2>/dev/null || true
              fi
            }
            trap stop_postgres EXIT
            ${secureFileSystem}/bin/local-control-secure-files exec-cluster-socket \
              "$new_cluster" \
              18 \
              "$socket_directory" \
              ${pkgs.postgresql_18}/bin/postgres \
              -D . \
              -h "" \
              -k @socket@ \
              -p 55439 \
              > "$postgres_log" 2>&1 &
            postgres_pid=$!
            postgres_ready=""
            for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
              if ${pkgs.postgresql_18}/bin/pg_isready \
                -h "$socket_directory" \
                -p 55439 >/dev/null 2>&1; then
                postgres_ready=1
                break
              fi
              ${pkgs.coreutils}/bin/sleep 1
            done
            if [ -z "$postgres_ready" ]; then
              ${pkgs.coreutils}/bin/cat "$postgres_log" >&2
              printf 'The descriptor-validated PostgreSQL socket path did not become ready.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/touch "$out"
          '';

      checks.local-control-private-path-validation =
        pkgs.runCommand "local-control-private-path-validation" { }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-private-path-validation"
            real_directory="$test_root/real"
            target_directory="$test_root/target"
            linked_directory="$test_root/linked"
            bad_mode_directory="$test_root/bad-mode"
            private_file="$test_root/private-file"
            linked_file="$test_root/linked-file"
            ${pkgs.coreutils}/bin/mkdir -p "$target_directory" "$bad_mode_directory"

            ${privatePathGuard}/bin/local-control-private-path \
              ensure-directory "$real_directory" "real directory"
            [ "$(${pkgs.coreutils}/bin/stat -c '%a' "$real_directory")" = 700 ]

            ${pkgs.coreutils}/bin/ln -s "$target_directory" "$linked_directory"
            if ${privatePathGuard}/bin/local-control-private-path \
              ensure-directory "$linked_directory" "linked directory" >/dev/null 2>&1; then
              printf 'A directory symlink was accepted by the ensure guard.\n' >&2
              exit 1
            fi
            if ${privatePathGuard}/bin/local-control-private-path \
              validate-directory "$linked_directory" "linked directory" >/dev/null 2>&1; then
              printf 'A directory symlink was accepted by the validation guard.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/chmod 755 "$bad_mode_directory"
            if ${privatePathGuard}/bin/local-control-private-path \
              validate-directory "$bad_mode_directory" "bad mode directory" >/dev/null 2>&1; then
              printf 'A group-readable directory was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/printf 'private\n' > "$private_file"
            ${pkgs.coreutils}/bin/chmod 600 "$private_file"
            ${privatePathGuard}/bin/local-control-private-path \
              validate-file "$private_file" "private file" 600
            public_file="$test_root/public-file"
            ${pkgs.coreutils}/bin/printf 'public\n' > "$public_file"
            ${pkgs.coreutils}/bin/chmod 644 "$public_file"
            ${privatePathGuard}/bin/local-control-private-path \
              validate-file "$public_file" "public file" 644
            ${pkgs.coreutils}/bin/ln -s "$private_file" "$linked_file"
            if ${privatePathGuard}/bin/local-control-private-path \
              validate-file "$linked_file" "linked file" 600 >/dev/null 2>&1; then
              printf 'A file symlink was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/touch "$out"
          '';

      checks.local-control-environment-validation =
        pkgs.runCommand "local-control-environment-validation" { }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-environment-validation"
            environment_file="$test_root/environment"
            ${pkgs.coreutils}/bin/mkdir -p "$test_root"

            write_valid_environment() {
              ${pkgs.coreutils}/bin/printf '%s\n' \
                'LOCAL_CONTROL_PROJECT_DIRECTORY=/tmp/source' \
                'LOCAL_CONTROL_DATABASE_URL=database-value' \
                'LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=LOCAL_CONTROL_DB_URL' \
                'LOCAL_CONTROL_SCHEMA_COMMAND=schema command' \
                'LOCAL_CONTROL_API_COMMAND=api command' \
                'LOCAL_CONTROL_WORKER_COMMAND=worker command' \
                'LOCAL_CONTROL_FRONTEND_COMMAND=frontend command' \
                'LOCAL_CONTROL_PREPARE_COMMAND=prepare command' \
                'LOCAL_CONTROL_PREPARATION_INPUT=input-a' \
                'LOCAL_CONTROL_READINESS_URL=http://127.0.0.1/readiness' \
                "''${1:+SERVICE_PROXY_ATTESTATION=attestation}" > "$environment_file"
              ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
            }

            assert_rejected() {
              if ${environmentSnapshot}/bin/local-control-environment-snapshot read \
                "$environment_file" "$1" >/dev/null 2>&1; then
                printf 'Malformed environment input was accepted: %s\n' "$2" >&2
                exit 1
              fi
            }

            : > "$environment_file"
            ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
            assert_rejected disabled empty

            ${pkgs.coreutils}/bin/printf 'not a record\n' > "$environment_file"
            assert_rejected disabled malformed

            write_valid_environment
            ${pkgs.coreutils}/bin/printf 'LOCAL_CONTROL_API_COMMAND=duplicate\n' >> "$environment_file"
            assert_rejected disabled duplicate

            write_valid_environment
            ${pkgs.coreutils}/bin/printf 'UNSUPPORTED_SETTING=reject\n' >> "$environment_file"
            assert_rejected disabled unsupported

            ${pkgs.coreutils}/bin/printf 'LOCAL_CONTROL_PROJECT_DIRECTORY=/tmp/source\r\n' > "$environment_file"
            assert_rejected disabled carriage-return

            write_valid_environment
            ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$environment_file" disabled >/dev/null
            write_valid_environment enabled
            ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$environment_file" enabled >/dev/null
            write_valid_environment
            ${pkgs.coreutils}/bin/mkfifo "$test_root/fifo"
            if ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$test_root/fifo" disabled >/dev/null 2>&1; then
              printf 'A FIFO environment input was accepted.\n' >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/ln -s "$environment_file" "$test_root/linked"
            if ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$test_root/linked" disabled >/dev/null 2>&1; then
              printf 'A symlinked environment input was accepted.\n' >&2
              exit 1
            fi

            runtime_root="$test_root/runtime"
            generation_root="$runtime_root/generation-1"
            generation_environment="$generation_root/service/environment"
            ${pkgs.coreutils}/bin/mkdir -p "$generation_root/service"
            ${pkgs.coreutils}/bin/chmod 700 "$runtime_root" "$generation_root" "$generation_root/service"
            write_valid_environment
            ${pkgs.coreutils}/bin/cp "$environment_file" "$generation_environment"
            ${pkgs.coreutils}/bin/chmod 600 "$generation_environment"
            ${pkgs.coreutils}/bin/ln -s generation-1 "$runtime_root/current"
            ${secureFileSystem}/bin/local-control-secure-files inspect-generation-file \
              "$runtime_root/current/service/environment" 600 >/dev/null
            ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$runtime_root/current/service/environment" disabled >/dev/null

            ${pkgs.coreutils}/bin/rm "$runtime_root/current"
            ${pkgs.coreutils}/bin/ln -s ../outside "$runtime_root/current"
            if ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$runtime_root/current/service/environment" disabled >/dev/null 2>&1; then
              printf 'An escaping current-generation link was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/rm "$runtime_root/current"
            ${pkgs.coreutils}/bin/chmod 750 "$generation_root"
            ${pkgs.coreutils}/bin/ln -s generation-1 "$runtime_root/current"
            if ${environmentSnapshot}/bin/local-control-environment-snapshot read \
              "$runtime_root/current/service/environment" disabled >/dev/null 2>&1; then
              printf 'A non-private current-generation directory was accepted.\n' >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/chmod 700 "$generation_root"

            race_source="$test_root/race-source"
            ${pkgs.coreutils}/bin/mkdir -p "$race_source"
            ${pkgs.coreutils}/bin/printf 'stable\n' > "$race_source/input"
            ${pkgs.coreutils}/bin/chmod 600 "$race_source/input"
            (
              for race_iteration in $(${pkgs.coreutils}/bin/seq 1 100); do
                ${pkgs.coreutils}/bin/printf 'stable\n' > "$race_source/input"
                ${pkgs.coreutils}/bin/printf 'changed\n' > "$race_source/input"
              done
            ) &
            race_writer=$!
            while kill -0 "$race_writer" 2>/dev/null; do
              race_read="$(${secureFileSystem}/bin/local-control-secure-files read-file \
                "$race_source/input" 600 2>/dev/null || true)"
              case "$race_read" in
                ""|stable|changed)
                  ;;
                *)
                  printf 'A raced file read produced an unstable result.\n' >&2
                  exit 1
                  ;;
              esac
            done
            wait "$race_writer"
            ${sourceTreeSnapshot}/bin/local-control-source-snapshot "$race_source" >/dev/null

            ${pkgs.coreutils}/bin/touch "$out"
          '';

      checks.local-control-proxy-environment = pkgs.runCommand "local-control-proxy-environment" { } ''
        set -euo pipefail

        test_root="$TMPDIR/local-control-proxy-environment"
        pki_directory="$test_root/pki"
        environment_file="$test_root/environment"
        linked_environment="$test_root/linked-environment"
        ${pkgs.coreutils}/bin/mkdir -m 700 -p "$pki_directory"
        ${pkgs.coreutils}/bin/printf 'ca\n' > "$pki_directory/ca.crt"
        ${pkgs.coreutils}/bin/printf 'certificate\n' > "$pki_directory/server.crt"
        ${pkgs.coreutils}/bin/printf 'key\n' > "$pki_directory/server.key"
        ${pkgs.coreutils}/bin/chmod 644 "$pki_directory/ca.crt" "$pki_directory/server.crt"
        ${pkgs.coreutils}/bin/chmod 600 "$pki_directory/server.key"

        write_valid_environment() {
          ${pkgs.coreutils}/bin/printf '%s\n' \
            'SERVICE_DATABASE_URL=postgresql://fixture.invalid/control' \
            'SERVICE_PROXY_ATTESTATION=fixture-proxy-attestation-0123456789abcdef' \
            'SERVICE_RELEASE_ID=0123456789abcdef0123456789abcdef01234567' \
            > "$environment_file"
          ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
        }

        write_valid_environment
        ${secureFileSystem}/bin/local-control-secure-files exec-proxy \
          "$pki_directory" \
          "$environment_file" \
          ${pkgs.bash}/bin/bash \
          -c '
            [ "$SERVICE_PROXY_ATTESTATION" = fixture-proxy-attestation-0123456789abcdef ]
            [ -r "$LOCAL_CONTROL_PROXY_CA" ]
            [ -r "$LOCAL_CONTROL_PROXY_CERT" ]
            [ -r "$LOCAL_CONTROL_PROXY_KEY" ]
          '

        ${pkgs.coreutils}/bin/printf '%s\n' \
          'SERVICE_PROXY_ATTESTATION=fixture-proxy-attestation-0123456789abcdef' \
          'SERVICE_PROXY_ATTESTATION=fixture-proxy-attestation-duplicated-value' \
          > "$environment_file"
        ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
        if ${secureFileSystem}/bin/local-control-secure-files exec-proxy \
          "$pki_directory" "$environment_file" ${pkgs.coreutils}/bin/true \
          >/dev/null 2>&1; then
          printf 'A duplicated proxy attestation was accepted.\n' >&2
          exit 1
        fi

        write_valid_environment
        ${pkgs.coreutils}/bin/ln -s "$environment_file" "$linked_environment"
        if ${secureFileSystem}/bin/local-control-secure-files exec-proxy \
          "$pki_directory" "$linked_environment" ${pkgs.coreutils}/bin/true \
          >/dev/null 2>&1; then
          printf 'A symlinked proxy environment was accepted.\n' >&2
          exit 1
        fi

        ${pkgs.coreutils}/bin/touch "$out"
      '';

      checks.local-control-preparation-proof-validation =
        pkgs.runCommand "local-control-preparation-proof-validation"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.git
            ];
          }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-preparation-proof-validation"
            project="$test_root/project"
            environment_file="$test_root/environment"
            ${pkgs.coreutils}/bin/mkdir -p "$project/empty-directory"
            git -C "$project" init -q
            git -C "$project" config user.email test@example.invalid
            git -C "$project" config user.name test
            ${pkgs.coreutils}/bin/printf 'ignored.txt\n' > "$project/.gitignore"
            ${pkgs.coreutils}/bin/printf 'tracked-input\n' > "$project/source.txt"
            git -C "$project" add .gitignore source.txt
            git -C "$project" commit -qm initial
            ${pkgs.coreutils}/bin/printf 'ignored-secret-content\n' > "$project/ignored.txt"
            ${pkgs.coreutils}/bin/printf 'untracked-input\n' > "$project/untracked.txt"

            status_output="$(git -C "$project" status --porcelain=v1 --ignored)"
            case "$status_output" in
              *'!! ignored.txt'*'?? untracked.txt'*|*'?? untracked.txt'*'!! ignored.txt'*)
                ;;
              *)
                printf 'The ignored and untracked fixture inputs were not present at proof time.\n' >&2
                exit 1
                ;;
            esac

            write_environment() {
              ${pkgs.coreutils}/bin/printf '%s\n' \
                "LOCAL_CONTROL_PROJECT_DIRECTORY=$1" \
                "LOCAL_CONTROL_DATABASE_URL=$2" \
                'LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=LOCAL_CONTROL_DB_URL' \
                'LOCAL_CONTROL_SCHEMA_COMMAND=schema command' \
                "LOCAL_CONTROL_API_COMMAND=$3" \
                'LOCAL_CONTROL_WORKER_COMMAND=worker command' \
                'LOCAL_CONTROL_FRONTEND_COMMAND=frontend command' \
                'LOCAL_CONTROL_PREPARE_COMMAND=prepare command' \
                'LOCAL_CONTROL_PREPARATION_INPUT=input-a' \
                'LOCAL_CONTROL_READINESS_URL=http://127.0.0.1/readiness' \
                "''${4:+SERVICE_PROXY_ATTESTATION=$4}" > "$environment_file"
              ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
            }

            proof_for() {
              write_environment "$1" "$2" "$3" "''${4:-}"
              ${pkgs.coreutils}/bin/env -i \
                HOME="$TMPDIR" \
                PATH=/no-such-path \
                ${preparationProof}/bin/local-control-preparation-proof compute \
                "$5" "$6" "$environment_file"
            }

            initial_proof="$(proof_for "$project" database-value 'api command' secret-attestation static-a enabled)"
            [ "$(${pkgs.coreutils}/bin/printf '%s' "$initial_proof" | ${pkgs.coreutils}/bin/wc -c)" -eq 64 ]
            case "$initial_proof" in
              *[!0-9a-fA-F]*)
                printf 'The preparation proof was not a hexadecimal digest.\n' >&2
                exit 1
                ;;
            esac
            case "$initial_proof" in
              *secret-attestation*|*database-value*|*ignored-secret-content*)
                printf 'A raw setting escaped into the preparation proof.\n' >&2
                exit 1
                ;;
            esac

            ${pkgs.coreutils}/bin/printf 'changed-ignored-content\n' > "$project/ignored.txt"
            ignored_changed_proof="$(proof_for "$project" database-value 'api command' secret-attestation static-a enabled)"
            [ "$initial_proof" != "$ignored_changed_proof" ]
            ${pkgs.coreutils}/bin/printf 'changed-untracked-content\n' > "$project/untracked.txt"
            untracked_changed_proof="$(proof_for "$project" database-value 'api command' secret-attestation static-a enabled)"
            [ "$ignored_changed_proof" != "$untracked_changed_proof" ]
            ${pkgs.coreutils}/bin/chmod 700 "$project/empty-directory"
            mode_changed_proof="$(proof_for "$project" database-value 'api command' secret-attestation static-a enabled)"
            [ "$untracked_changed_proof" != "$mode_changed_proof" ]
            api_changed_proof="$(proof_for "$project" database-value 'changed api command' secret-attestation static-a enabled)"
            [ "$mode_changed_proof" != "$api_changed_proof" ]

            write_environment "$project" database-value 'api command' secret-attestation
            ${pkgs.coreutils}/bin/printf 'UNSUPPORTED_SETTING=reject-me\n' >> "$environment_file"
            if ${preparationProof}/bin/local-control-preparation-proof compute static-a enabled "$environment_file" >/dev/null 2>&1; then
              printf 'An unsupported environment setting was accepted.\n' >&2
              exit 1
            fi

            write_environment "$project" database-value 'api command' ""
            disabled_proof="$(
              ${pkgs.coreutils}/bin/env -i \
                HOME="$TMPDIR" \
                PATH=/no-such-path \
                ${preparationProof}/bin/local-control-preparation-proof compute \
                static-a disabled "$environment_file"
            )"
            [ "$(${pkgs.coreutils}/bin/printf '%s' "$disabled_proof" | ${pkgs.coreutils}/bin/wc -c)" -eq 64 ]

            write_environment "$project" database-value 'api command' ""
            ${pkgs.coreutils}/bin/printf 'SERVICE_PROXY_ATTESTATION=unexpected\n' >> "$environment_file"
            if ${preparationProof}/bin/local-control-preparation-proof compute static-a disabled "$environment_file" >/dev/null 2>&1; then
              printf 'A proxy setting was accepted while the proxy was disabled.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/mkdir -p "$test_root/non-git"
            ${pkgs.coreutils}/bin/printf 'source\n' > "$test_root/non-git/source.txt"
            write_environment "$test_root/non-git" database-value 'api command' ""
            if ${preparationProof}/bin/local-control-preparation-proof compute static-a disabled "$environment_file" >/dev/null 2>&1; then
              printf 'A non-Git source tree was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/mkdir -p "$project/linked-target"
            ${pkgs.coreutils}/bin/ln -s linked-target "$project/linked-directory"
            write_environment "$project" database-value 'api command' secret-attestation
            if ${preparationProof}/bin/local-control-preparation-proof compute static-a enabled "$environment_file" >/dev/null 2>&1; then
              printf 'A source symlink was accepted.\n' >&2
              exit 1
            fi

            ${pkgs.coreutils}/bin/touch "$out"
          '';

      checks.local-control-preparation-gate-validation =
        pkgs.runCommand "local-control-preparation-gate-validation"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.git
            ];
          }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-preparation-gate-validation"
            project="$test_root/project"
            environment_file="$test_root/environment"
            state_directory="$test_root/state"
            preparation_stamp="$state_directory/preparation-stamp"
            marker="$state_directory/marker"
            ${pkgs.coreutils}/bin/mkdir -p "$project" "$state_directory"
            ${pkgs.coreutils}/bin/chmod 700 "$state_directory"
            git -C "$project" init -q
            git -C "$project" config user.email test@example.invalid
            git -C "$project" config user.name test
            ${pkgs.coreutils}/bin/printf 'source\n' > "$project/source.txt"
            git -C "$project" add source.txt
            git -C "$project" commit -qm initial
            ${pkgs.coreutils}/bin/printf '%s\n' \
              "LOCAL_CONTROL_PROJECT_DIRECTORY=$project" \
              'LOCAL_CONTROL_DATABASE_URL=database-value' \
              'LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=LOCAL_CONTROL_DB_URL' \
              'LOCAL_CONTROL_SCHEMA_COMMAND=schema command' \
              'LOCAL_CONTROL_API_COMMAND=api command' \
              'LOCAL_CONTROL_WORKER_COMMAND=worker command' \
              'LOCAL_CONTROL_FRONTEND_COMMAND=frontend command' \
              'LOCAL_CONTROL_PREPARE_COMMAND=prepare command' \
              'LOCAL_CONTROL_PREPARATION_INPUT=input-a' \
              'LOCAL_CONTROL_READINESS_URL=http://127.0.0.1/readiness' \
              'SERVICE_PROXY_ATTESTATION=attestation' > "$environment_file"
            ${pkgs.coreutils}/bin/chmod 600 "$environment_file"

            run_gate() {
              GATE_MARKER="$marker" \
                ${preparationGate}/bin/local-control-service-gate \
                "$environment_file" "$preparation_stamp" "$state_directory" \
                static-gate enabled \
                ${pkgs.bash}/bin/bash -c 'printf ran > "$GATE_MARKER"'
            }

            run_gate
            [ ! -f "$marker" ]

            state="$(${preparationProof}/bin/local-control-preparation-proof compute \
              static-gate enabled "$environment_file")"
            ${pkgs.coreutils}/bin/printf '%s\n' stale > "$preparation_stamp"
            ${pkgs.coreutils}/bin/chmod 600 "$preparation_stamp"
            run_gate
            [ ! -f "$marker" ]

            ${pkgs.coreutils}/bin/printf '%s\n' "$state" > "$preparation_stamp"
            ${pkgs.coreutils}/bin/chmod 600 "$preparation_stamp"
            run_gate
            [ -f "$marker" ]

            ${pkgs.coreutils}/bin/printf '%s\n' \
              "LOCAL_CONTROL_PROJECT_DIRECTORY=$project" \
              'LOCAL_CONTROL_DATABASE_URL=database-value' \
              'LOCAL_CONTROL_DATABASE_ENVIRONMENT_VARIABLE=LOCAL_CONTROL_DB_URL' \
              'LOCAL_CONTROL_SCHEMA_COMMAND=schema command' \
              'LOCAL_CONTROL_API_COMMAND=api command' \
              'LOCAL_CONTROL_WORKER_COMMAND=worker command' \
              'LOCAL_CONTROL_FRONTEND_COMMAND=frontend command' \
              'LOCAL_CONTROL_PREPARE_COMMAND=prepare command' \
              'LOCAL_CONTROL_PREPARATION_INPUT=input-a' \
              'LOCAL_CONTROL_READINESS_URL=http://127.0.0.1/readiness' > "$environment_file"
            ${pkgs.coreutils}/bin/chmod 600 "$environment_file"
            disabled_state="$(${preparationProof}/bin/local-control-preparation-proof compute \
              static-gate disabled "$environment_file")"
            disabled_stamp="$state_directory/disabled-stamp"
            ${pkgs.coreutils}/bin/printf '%s\n' "$disabled_state" > "$disabled_stamp"
            ${pkgs.coreutils}/bin/chmod 600 "$disabled_stamp"
            disabled_marker="$state_directory/disabled-marker"
            GATE_MARKER="$disabled_marker" \
              ${preparationGate}/bin/local-control-service-gate \
              "$environment_file" "$disabled_stamp" "$state_directory" \
              static-gate disabled \
              ${pkgs.bash}/bin/bash -c 'printf ran > "$GATE_MARKER"'
            [ -f "$disabled_marker" ]

            ${pkgs.coreutils}/bin/touch "$out"
          '';
      checks.local-control-generated-activation =
        if pkgs.stdenv.hostPlatform.isDarwin then
          let
            activationHome = "/private/tmp/local-control-activation-${builtins.hashString "sha256" (builtins.readFile ../../homes/macbook-pro-m4/local/local-control.nix)}";
            homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ../../homes/macbook-pro-m4/local/local-control.nix
                {
                  home.username = "check-user";
                  home.homeDirectory = activationHome;
                  home.stateVersion = "24.11";
                  services.localControl.enable = true;
                }
              ];
            };
            activationScript = pkgs.writeText "local-control-generated-activation-script" homeConfiguration.config.home.activation.localControlState.data;
          in
          pkgs.runCommand "local-control-generated-activation"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnused
              ];
            }
            ''
              set -euo pipefail
              activation_runtime_home="$TMPDIR/local-control-activation-home"
              activation_runtime_script="$TMPDIR/local-control-activation-script"
              ${pkgs.gnused}/bin/sed \
                "s|${activationHome}|$activation_runtime_home|g" \
                ${activationScript} > "$activation_runtime_script"
              ${pkgs.bash}/bin/bash -n "$activation_runtime_script"
              ${pkgs.bash}/bin/bash "$activation_runtime_script"

              ${pkgs.coreutils}/bin/touch "$activation_runtime_home/.local/state/local-control/logs/proxy.out.log"
              ${pkgs.coreutils}/bin/chmod 644 "$activation_runtime_home/.local/state/local-control/logs/proxy.out.log"
              ${pkgs.bash}/bin/bash "$activation_runtime_script"
              [ "$(${pkgs.coreutils}/bin/stat -c '%a' "$activation_runtime_home/.local/state/local-control/logs/proxy.out.log")" = 600 ]

              ${pkgs.bash}/bin/bash "$activation_runtime_script"

              activation_state="$activation_runtime_home/.local/state/local-control"
              [ -d "$activation_state" ]
              [ -L "$activation_state/dashboard-current" ]
              [ "$(readlink "$activation_state/dashboard-current")" = current/dashboard ]
              [ -f "$activation_state/database/PG_VERSION" ]
              [ -f "$activation_state/pki/ca.crt" ]
              [ -f "$activation_state/pki/ca.key" ]
              [ -f "$activation_state/pki/server.crt" ]
              [ -f "$activation_state/pki/server.key" ]
              [ -f "$activation_state/pki/client.crt" ]
              [ -f "$activation_state/pki/client.key" ]
              [ ! -e "$activation_state/environment" ]
              ${pkgs.coreutils}/bin/touch "$out"
            ''
        else
          pkgs.runCommand "local-control-generated-activation-not-applicable" { } ''
            touch "$out"
          '';
    };
}
