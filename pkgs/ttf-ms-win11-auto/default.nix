{
  lib,
  stdenv,
  fetchurl,
  p7zip,
  acceptEula ? true,
}:
stdenv.mkDerivation rec {
  pname = "ttf-ms-win11-auto";
  version = "1";

  sourceRoot = ".";

  strictDeps = true;

  # Because this must download a very large ISO file, and the actual "build"
  # is just unpacking it, it is best to avoid remote builds.
  # On nixbuild.net especially, building this derivation
  # is likely to fail by running out of memory.
  preferLocalBuild = true;

  eula =
    assert lib.assertMsg acceptEula ''
      You must override this package and accept the EULA. (ttf-ms-win11)
      <http://corefonts.sourceforge.net/eula.htm>
    '';
    fetchurl {
      url = "http://corefonts.sourceforge.net/eula.htm";
      sha256 = "1aqbcnl032g2hd7iy56cs022g47scb0jxxp3mm206x1yqc90vs1c";
    };

  src = fetchurl {
    # <https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise>
    # <https://www.microsoft.com/en-us/evalcenter/download-windows-10-enterprise>
    url = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/22631.2428.231001-0608.23H2_NI_RELEASE_SVC_REFRESH_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso";
    sha256 = "sha256-yNvJa2HQTIsB+vbOB5T98zllx7NQ6qPrHmaXAZkClFw=";
  };

  nativeBuildInputs = [ p7zip ];

  unpackPhase = ''
    runHook preUnpack

    echo "Extracting iso..."
    7z x ${src} sources/install.wim

    echo "Extracting font and license files..."
    7z e sources/install.wim Windows/{Fonts/"*".{ttf,ttc},System32/Licenses/neutral/"*"/"*"/license.rtf} -ofonts

    echo "Cleaning up..."
    rm -rf sources

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out

    echo "Installing to '$out'"
    install -Dm444 fonts/*.{ttf,ttc} -t "$out/share/fonts/truetype"

    echo "Installing license files..."
    install -Dm444 fonts/license.rtf -t "$out/share/licenses/${pname}"
    install -Dm444 '${eula}' -t "$out/share/licenses/${pname}"

    echo "Cleaning up..."
    rm -rf fonts

    runHook postInstall
  '';

  meta = {
    description = "Microsoft's TrueType fonts from Windows 11";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    platforms = lib.platforms.all;
    license = lib.licenses.unfreeRedistributable;
  };
}
