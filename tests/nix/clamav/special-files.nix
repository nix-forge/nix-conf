{ pkgs }:
pkgs.runCommand "clamav-special-files"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.findutils
      (pkgs.python3.withPackages (ps: [
        ps.pytest
        (import ../../../lib/python/notification-process/package.nix { inherit pkgs; })
      ]))
    ];
    CLAMAV_BIN = "${pkgs.clamav}/bin";
    CLAMAV_SCAN_SCRIPT = ../../../modules/nixos/security/clamav_scan.py;
    CLAMAV_FIXTURE_LAUNCHER = ./activate_daemon.py;
  }
  (
    (import ../../../lib/templates/text.nix) ./scripts/clamav-special-files.sh {
      check_special_files_py = ./check_special_files.py;
    }
  )
