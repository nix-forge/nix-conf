_: {
  perSystem =
    { pkgs, ... }:
    let
      postgresClusterValidator =
        (import ../../lib/local-control/postgres-cluster-validator.nix { }).mkPostgresClusterValidator
          pkgs;
    in
    {
      checks.local-control-postgres-validation =
        pkgs.runCommand "local-control-postgres-validation" { }
          ''
            set -euo pipefail

            test_root="$TMPDIR/local-control-postgres-validation"
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
              ${postgresClusterValidator}/bin/local-control-validate-postgres-cluster "$existing_cluster"

            if ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${postgresClusterValidator}/bin/local-control-validate-postgres-cluster "$new_cluster"; then
              printf 'An uninitialized PostgreSQL directory was accepted.\n' >&2
              exit 1
            fi

            # Exercise the same post-initialization branch used by activation:
            # an empty, private directory is initialized and then validated.
            ${pkgs.postgresql_18}/bin/initdb \
              --pgdata="$new_cluster" \
              --auth-local=trust \
              --auth-host=scram-sha-256 \
              --encoding=UTF8 \
              --no-locale >/dev/null
            ${pkgs.coreutils}/bin/env -i \
              HOME="$TMPDIR" \
              PATH=/no-such-path \
              ${postgresClusterValidator}/bin/local-control-validate-postgres-cluster "$new_cluster"

            ${pkgs.coreutils}/bin/touch "$out"
          '';
    };
}
