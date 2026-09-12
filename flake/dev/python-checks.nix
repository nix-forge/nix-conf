{ ... }: {
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
        ../../modules/nixos/hardware/scripts/disable-bluetooth-pairing.sh
        ../../modules/home/scripts/karakeep-launchd.sh
        ../../modules/home/scripts/configure-spotify-quality.sh
        ../../hosts/nixos/desktop/minidv/minidv-supervise.py
        ../../hosts/nixos/desktop/minidv/minidv-finalize.sh
        ../../homes/macbook-pro-m4/local/dev_vm_host.py
        ../../hosts/nixos/desktop/local/storage/backup-helper.py
        (pkgs.lib.fileset.fileFilter (file: file.hasExt "py") ../../scripts)
      ];
      nativeBuildInputs = with pkgs; [
        bash
        coreutils
        dbus
        diffutils
        findutils
        git
        procps
        util-linux
        gawk
        gnugrep
        jq
        libxml2
        openssh
        perl
        restic
      ];
    };
  };
}
