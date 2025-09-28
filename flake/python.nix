{ python3, openssl }:
let
  python_pkg = python3.override { inherit openssl; };
in
rec {
  additionalPythonPackages =
    ps: with ps; [
      # Base
      pip
      setuptools
      wheel

      # HTTP
      requests
      types-requests
    ];
  python_with_pkgs = python_pkg.withPackages additionalPythonPackages;
  python_path = "${python_with_pkgs}/${python_with_pkgs.sitePackages}";
}
