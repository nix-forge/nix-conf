_: {
  mkPostgresClusterValidator =
    pkgs:
    pkgs.writeShellApplication {
      name = "local-control-validate-postgres-cluster";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.postgresql_18
      ];
      text = ''
        set -euo pipefail
        if [ "$#" -ne 1 ]; then
          printf 'Exactly one PostgreSQL data directory is required.\n' >&2
          exit 64
        fi

        postgres_data_dir="$1"
        if [ -L "$postgres_data_dir" ] || [ ! -d "$postgres_data_dir" ]; then
          exit 1
        fi
        if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' "$postgres_data_dir" )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
          exit 1
        fi
        postgres_dir_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' "$postgres_data_dir" )"
        if (( (8#$postgres_dir_mode & 0077) != 0 )); then
          exit 1
        fi
        for postgres_control_file in PG_VERSION postgresql.conf pg_hba.conf pg_ident.conf; do
          postgres_control_path="$postgres_data_dir/$postgres_control_file"
          if [ -L "$postgres_control_path" ] || [ ! -f "$postgres_control_path" ]; then
            exit 1
          fi
          if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' "$postgres_control_path" )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
            exit 1
          fi
          postgres_control_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' "$postgres_control_path" )"
          if (( (8#$postgres_control_mode & 0077) != 0 )); then
            exit 1
          fi
        done
        for postgres_control_dir in base global pg_wal; do
          postgres_control_path="$postgres_data_dir/$postgres_control_dir"
          if [ -L "$postgres_control_path" ] || [ ! -d "$postgres_control_path" ]; then
            exit 1
          fi
          if [ "$( ${pkgs.coreutils}/bin/stat -c '%u' "$postgres_control_path" )" != "$( ${pkgs.coreutils}/bin/id -u )" ]; then
            exit 1
          fi
          postgres_control_mode="$( ${pkgs.coreutils}/bin/stat -c '%a' "$postgres_control_path" )"
          if (( (8#$postgres_control_mode & 0077) != 0 )); then
            exit 1
          fi
        done
        postgres_major=""
        IFS= read -r postgres_major < "$postgres_data_dir/PG_VERSION" || true
        [ "$postgres_major" = 18 ] || exit 1
        ${pkgs.postgresql_18}/bin/pg_controldata "$postgres_data_dir" >/dev/null 2>&1
      '';
    };
}
