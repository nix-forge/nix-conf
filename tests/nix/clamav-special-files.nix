{ pkgs }:
pkgs.runCommand "clamav-special-files"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.findutils
      pkgs.python3Packages.pytest
    ];
    CLAMAV_BIN = "${pkgs.clamav}/bin";
    CLAMAV_SCAN_SCRIPT = ../../modules/nixos/security/clamav-scan.sh;
  }
  ''
    export HOME="$TMPDIR"
    pytest -q -o addopts= ${./check-clamav-special-files.py}
    touch "$out"
  ''
