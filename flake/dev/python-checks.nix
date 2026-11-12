_: {
  perSystem = { pkgs, ... }: {
    # Discover all root-owned test_*.py files. Generated-artifact and daemon
    # suites opt into separate checks; operational check_* probes are explicit.
    checks.python-tests = (import ../../tests/python-check.nix { inherit pkgs; }) {
      name = "python-behavior-tests";
      files = [
        ../../overlays/temporary/scripts/sign-signal-bundle.py
        ../../overlays/temporary/tests/prism-watch-result.py
        ../../overlays/temporary/tests/darwin-package-result.py
        ../../overlays/temporary/tests/deploy-watch-pair.py
        ../../overlays/temporary/tests/deploy-confirmation-path-result.py
        ../../overlays/temporary/tests/test_deploy_confirmation_path_result.py
        ../../overlays/temporary/tests/test_deploy_watch_pair.py
        ../../overlays/temporary/tests/test_darwin_package_result.py
        ../../overlays/temporary/tests/actual-css-result.py
        ../../overlays/temporary/tests/actual-runtime.py
        ../../overlays/temporary/tests/actual_log_redaction.py
        ../../overlays/temporary/tests/test_actual_proof.py
        ../../overlays/temporary/tests/test_prism_watch_result.py
        (pkgs.lib.fileset.fileFilter (
          file:
          file.hasExt "py"
          || file.hasExt "js"
          || file.hasExt "cjs"
          || file.hasExt "mjs"
          || file.hasExt "ts"
          || file.hasExt "cts"
          || file.hasExt "mts"
          || file.hasExt "sh"
          || pkgs.lib.hasSuffix ".py.in" file.name
          || pkgs.lib.hasSuffix ".sh.in" file.name
          || pkgs.lib.hasSuffix ".nix.in" file.name
        ) ../../tests)
        (pkgs.lib.fileset.fileFilter (
          file: file.hasExt "py" || file.hasExt "awk" || pkgs.lib.hasSuffix ".sh.in" file.name
        ) ../../modules)
        ../../modules/nixos/hardware/iocost-assets
        ../../modules/nixos/system/activation-safety-assets
        ../../modules/nixos/display-managers/scripts/prepare-tuigreet-cache.sh
        ../../modules/nixos/hardware/scripts/disable-bluetooth-pairing.sh
        ../../modules/home/desktop/wallpaper-catalog.json
        ../../modules/home/desktop/scripts/session-lock.sh
        ../../modules/home/desktop/scripts/desktop-session-lock.sh
        ../../modules/home/spotify-assets/configure-spotify-quality.sh
        ../../modules/home/browsers/helium/scripts/apply-preference-defaults.sh
        ../../homes/desktop/local/workstation-task.sh
        ../../homes/desktop/local/workstation_task_events.py
        ../../homes/desktop/local/scripts/workstation_nix.py
        ../../homes/desktop/local/cloud/google_drive.py
        ../../homes/desktop/local/workspace-services/scripts/retire-unit-preview.sh
        ../../hosts/nixos/desktop/local/scripts/retire-boot-repair.sh
        ../../hosts/nixos/desktop/local/network/scripts/retire-dnssec-preview.sh
        ../../homes/desktop/local/workspace-services/runner.py
        ../../homes/desktop/local/codex-resources/scripts
        ../../hosts/shared/local/network.json
        ../../hosts/nixos/desktop/local/storage/backup_helper.py
        ../../hosts/nixos/desktop/local/storage/root_scrub.py
        ../../hosts/nixos/desktop/local/storage/scripts/export_homelab_databases.py
        ../../hosts/nixos/desktop/local/storage/scripts/restic-lock-wait.sh
        ../../hosts/nixos/desktop/local/storage/health.py
        ../../hosts/nixos/desktop/local/storage/capacity.py
        ../../hosts/nixos/desktop/local/storage/retention.py
        ../../hosts/nixos/desktop/local/storage/task_retention.py
        ../../hosts/nixos/desktop/local/storage/scripts/retire-preview.py
        ../../modules/shared/nix-settings-assets/install-root-credentials.sh
        ../../hosts/nixos/desktop/local/homelab/actual/scripts/actual-vault-open.sh
        ../../hosts/nixos/desktop/local/homelab/music/scripts/bootstrap_aurral.py
        ../../hosts/nixos/desktop/local/homelab/music/scripts/verify_listenbrainz_identity.py
        ../../hosts/nixos/desktop/local/homelab/music/scripts/rescan_shared_music_library.py
        ../../hosts/nixos/desktop/local/homelab/scripts/bootstrap_books.py
        ../../hosts/nixos/desktop/local/homelab/music/scripts/configure_audiomuse.py
        ../../hosts/nixos/desktop/local/homelab/music/scripts/music-discovery-bootstrap.sh
        ../../hosts/nixos/desktop/local/homelab/music/scripts/project-audiomuse-api-token.sh
        ../../hosts/nixos/desktop/local/homelab/scripts/ensure_homelab_dns.py
        ../../hosts/nixos/desktop/local/homelab/credentials/identity_reveal_worker.py
        ../../hosts/nixos/desktop/local/homelab/credentials/miniflux_seal_worker.py
        ../../hosts/nixos/desktop/local/homelab/credentials/identity_to_bitwarden.py
        ../../hosts/nixos/desktop/local/homelab/credentials/miniflux_to_bitwarden.py
        ../../hosts/nixos/desktop/local/homelab/credentials/homelab_to_bitwarden.py
        ../../hosts/nixos/desktop/local/homelab/credentials/remote-read-sources.sh
        ../../hosts/nixos/desktop/local/secrets
        ../../hosts/nixos/raspberry-pi/local/secrets
        ../../hosts/nixos/desktop/local/homelab/music/scripts/prepare-music-discovery-directories.sh
        ../../hosts/nixos/desktop/local/homelab/music/scripts/resolve-navidrome-plugin-user-ids.sh
        ../../hosts/shared/local/justfile
        ../../hosts/nixos/desktop/local/storage/scripts/prepare_desktop_installer.py
        ../../hosts/nixos/desktop/local/storage/scripts/desktop-installer-flake.nix.in
        ../../justfile
        (pkgs.lib.fileset.fileFilter (
          file: file.hasExt "py" || pkgs.lib.hasSuffix ".nix.in" file.name
        ) ../../scripts)
        ../../site/reference.py
      ];
      testPaths = [
        "tests"
        "overlays/temporary/tests/test_prism_watch_result.py"
        "overlays/temporary/tests/test_actual_proof.py"
        "overlays/temporary/tests/test_darwin_package_result.py"
        "overlays/temporary/tests/test_deploy_watch_pair.py"
        "overlays/temporary/tests/test_deploy_confirmation_path_result.py"
      ];
      nativeBuildInputs =
        with pkgs;
        [
          bash
          coreutils
          curl
          dbus
          diffutils
          file
          findutils
          imagemagick
          inetutils
          gawk
          git
          gnugrep
          jq
          just
          libxml2
          nodejs_24
          openssh
          perl
          restic
          util-linux
          procps
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.systemd ];
    };
  };
}
