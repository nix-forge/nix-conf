_: {
  perSystem = { pkgs, ... }: {
    # Discover all root-owned test_*.py files. Generated-artifact and daemon
    # suites opt into separate checks; operational check_* probes are explicit.
    checks.python-tests = (import ../../tests/python-check.nix { inherit pkgs; }) {
      name = "python-behavior-tests";
      files = [
        (pkgs.lib.fileset.fileFilter (file: file.hasExt "py") ../../tests)
        (pkgs.lib.fileset.fileFilter (
          file: file.hasExt "py" || pkgs.lib.hasSuffix ".sh.in" file.name
        ) ../../modules)
        ../../modules/nixos/display-managers/scripts/prepare-tuigreet-cache.sh
        ../../modules/nixos/hardware/scripts/disable-bluetooth-pairing.sh
        ../../modules/home/desktop/wallpaper-catalog.json
        ../../modules/home/desktop/scripts/session-lock.sh
        ../../modules/home/scripts/karakeep-launchd.sh
        ../../modules/home/scripts/configure-spotify-quality.sh
        ../../homes/macbook-pro-m4/local/dev_vm_host.py
        ../../hosts/nixos/desktop/local/storage/backup-helper.py
        ../../hosts/nixos/desktop/local/storage/health.py
        ../../hosts/nixos/desktop/minidv/minidv-supervise.py
        ../../hosts/nixos/desktop/minidv/minidv-finalize.sh
        (pkgs.lib.fileset.fileFilter (file: file.hasExt "py") ../../scripts)
        ../../site/reference.py
      ];
      nativeBuildInputs = with pkgs; [
        bash
        coreutils
        dbus
        diffutils
        file
        findutils
        imagemagick
        gawk
        git
        gnugrep
        jq
        libxml2
        openssh
        perl
        restic
        util-linux
        procps
      ];
    };
  };
}
