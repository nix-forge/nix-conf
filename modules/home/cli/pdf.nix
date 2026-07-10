{ pkgs, ... }: {
  home.packages = [
    pkgs.poppler-utils

    pkgs.python3Packages.reportlab

    pkgs.python3Packages.pdfplumber
    pkgs.python3Packages.pypdf
  ];
}
