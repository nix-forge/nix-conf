{ python3, openssl }:
let
  python_pkg = python3.override { inherit openssl; };
in
rec {
  python_with_pkgs = python_pkg.withPackages (
    ps: with ps; [
      # Base
      pip
      setuptools
      wheel

      # HTTP
      requests
      types-requests
    ]
  );
  python_path = "${python_with_pkgs}/${python_with_pkgs.sitePackages}";
}
