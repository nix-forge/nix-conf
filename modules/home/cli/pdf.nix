{ lib, pkgs, ... }:
let
  pdfPython = pkgs.python3.withPackages (ps: [
    ps.reportlab
    ps.pillow
    ps.pdfplumber
    ps.pypdf
  ]);
in
{
  home.packages = [
    pkgs.poppler-utils
    # Expose a complete document runtime without replacing the development
    # module's python3 or depending on a global PYTHONPATH.
    (pkgs.linkFarm "pdf-python" [
      {
        name = "bin/pdf-python";
        path = lib.getExe' pdfPython "python3";
      }
      {
        name = "bin/pdfplumber";
        path = lib.getExe' pdfPython "pdfplumber";
      }
    ])
  ];
}
