{ lib, pkgs, ... }: {
  reason = "EmbedPDF 2.15 maps unembedded Latin serif and monospace fonts to Stirling's Noto Sans fallback.";
  upstream = "https://github.com/embedpdf/embed-pdf-viewer";
  removal = "Stirling bundles an EmbedPDF release that selects the correct local Latin fallback by requested font face.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  # Stirling 3.1.0 still pins EmbedPDF 2.15.1; both patched modules retain
  # the exact source hashes checked by the patch helper.
  affectedVersions = {
    from = "3.0.1";
    until = "3.1.1";
  };
  apply =
    package:
    package.overrideAttrs (old: {
      preBuild = (old.preBuild or "") + ''
        ${lib.getExe pkgs.python3} ${./patches/stirling_embedpdf_font_fallback.py} frontend/node_modules ${./patches/stirling-embedpdf-font-fallback.js.in}
      '';
    });
}
