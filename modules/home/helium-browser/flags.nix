{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  chromiumVersion = "150.0.7871.100";

  mkChromiumExtension =
    {
      id,
      name,
      version,
      hash,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "chromium-extension-${name}";
      inherit version;

      src = pkgs.fetchurl {
        name = "${id}-${version}.crx";
        url = "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&prodversion=${chromiumVersion}&x=id%3D${id}%26installsource%3Dondemand%26uc";
        inherit hash;
      };

      nativeBuildInputs = [
        pkgs.python3
        pkgs.unzip
      ];

      unpackPhase = ''
        runHook preUnpack

        python3 - "$src" extension.zip <<'PY'
        import pathlib
        import struct
        import sys

        crx = pathlib.Path(sys.argv[1]).read_bytes()
        if crx[:4] != b"Cr24":
            raise SystemExit("not a CRX file")

        version = struct.unpack("<I", crx[4:8])[0]
        if version == 2:
            public_key_len, signature_len = struct.unpack("<II", crx[8:16])
            offset = 16 + public_key_len + signature_len
        elif version == 3:
            header_len = struct.unpack("<I", crx[8:12])[0]
            offset = 12 + header_len
        else:
            raise SystemExit(f"unsupported CRX version: {version}")

        pathlib.Path(sys.argv[2]).write_bytes(crx[offset:])
        PY

        mkdir source
        unzip -q extension.zip -d source
        sourceRoot=source

        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"
        cp -R . "$out/"

        runHook postInstall
      '';
    };

  chromiumExtensions = [
    (mkChromiumExtension {
      id = "mnjggcdmjocbbbhaepdhchncahnbgone";
      name = "sponsorblock";
      version = "6.1.6";
      hash = "sha256-VYf+K2qZRhAcoN3nxu/nanVcXuW21uY9/EjH9zbNtP8=";
    })
    (mkChromiumExtension {
      id = "nngceckbapebfimnlniiiahkandclblb";
      name = "bitwarden";
      version = "2026.6.1";
      hash = "sha256-isQi2O13OUV39zR7Z1KkpKL7QJxPWbQw2lMLE7AO1E0=";
    })
    (mkChromiumExtension {
      id = "kgcjekpmcjjogibpjebkhaanilehneje";
      name = "karakeep";
      version = "1.2.11";
      hash = "sha256-Dx3pjWTbypns52vbMhefXNIZ0MRDT/JK7Ut5nEdDrLk=";
    })
    (mkChromiumExtension {
      id = "hlepfoohegkhhmjieoechaddaejaokhf";
      name = "refined-github";
      version = "26.7";
      hash = "sha256-+JF3aJ86r2RoKD8bFYLDi0ONPlyiTH9JrYdJ5Z106Ao=";
    })
  ];
in
{
  programs.helium.flags = [
    "--no-first-run"
    "--no-default-browser-check"
    "--disable-features=ChromeWhatsNewUI,OptimizationGuideModelDownloading,OptimizationHintsFetching,OptimizationTargetPrediction"
    "--load-extension=${lib.concatStringsSep "," (map toString chromiumExtensions)}"
  ]
  ++ lib.optionals isLinux [
    "--ozone-platform-hint=auto"
    "--enable-features=TouchpadOverscrollHistoryNavigation,VaapiVideoDecodeLinuxGL,VaapiVideoEncoder"
    "--ignore-gpu-blocklist"
    "--enable-zero-copy"
  ];
}
