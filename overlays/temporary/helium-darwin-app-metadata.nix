_: {
  reason = "The Darwin Helium recipe omits application metadata and mutates signed vendor code during fixup.";
  upstream = "https://github.com/schembriaiden/helium-browser-nix-flake/blob/ef91010a4fcc551b5cb24f52608dc8d45c527d9d/flake.nix";
  removal = "The selected Darwin Helium recipe declares mainDarwinApp and preserves the vendor bundle through strict deep signature verification.";
  reviewedRevision = "eb16551510c02303821b83f67b5692094aabe3c4";
  inputPath = [ "helium-browser-darwin" ];
  apply =
    package:
    package.overrideAttrs (old: {
      # Preserve the vendor resource seal and Developer ID identity.
      dontStrip = true;
      dontPatchShebangs = true;
      meta = {
        mainDarwinApp = "Helium.app";
      }
      // (old.meta or { });
    });
}
