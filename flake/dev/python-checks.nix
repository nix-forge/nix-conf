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
        ../../homes/macbook-pro-m4/local/dev_vm_host.py
        ../../hosts/nixos/desktop/local/storage/backup-helper.py
        (pkgs.lib.fileset.fileFilter (file: file.hasExt "py") ../../scripts)
      ];
      nativeBuildInputs = with pkgs; [
        bash
        coreutils
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
