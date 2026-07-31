{ pkgs, ... }: {
  home.packages = [
    pkgs.poppler-utils

    pkgs.python3Packages.reportlab

    # `doCheck` skips only pdfplumber's check phase. Drop native test inputs
    # too, otherwise Nix still builds pandas-stubs (whose install checks fail
    # with pytest 9 on Python 3.14) before it can build pdfplumber.
    (pkgs.python3Packages.pdfplumber.overridePythonAttrs (_: {
      doCheck = false;
      nativeCheckInputs = [ ];
    }))
    pkgs.python3Packages.pypdf
  ];
}
