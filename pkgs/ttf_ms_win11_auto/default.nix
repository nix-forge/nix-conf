{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,
  writeShellApplication,
  python3,
  openssl,
  gitMinimal,
}:
let
  pythonWithOpenSSL = python3.override { inherit openssl; };
  python = pythonWithOpenSSL.withPackages (ps: with ps; [ requests ]);
  updateScriptDrv = writeShellApplication {
    name = "update-ttf-ms-win11-auto";
    runtimeInputs = [
      python
      gitMinimal
    ];
    text = ''
      set -euo pipefail

      repo_root="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
      package_file="$repo_root/pkgs/ttf_ms_win11_auto/default.nix"

      if [[ ! -f "$package_file" ]]; then
        echo "ERROR ttf-ms-win11-auto.update: Package file not found: $package_file" >&2
        exit 1
      fi

      exec ${lib.getExe python} ${./update.py} --package-file "$package_file" "$@"
    '';
  };
in
stdenvNoCC.mkDerivation rec {
  pname = "ttf-ms-win11-auto";
  version = "10.0.26200.6584";

  strictDeps = true;

  # Because this must download a very large ISO file, and the actual "build"
  # is just unpacking it, it is best to avoid remote builds.
  # On nixbuild.net especially, building this derivation
  # is likely to fail by running out of memory.
  preferLocalBuild = true;

  src = fetchurl {
    # <https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise>
    url = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26200.6584.250915-1905.25h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso";
    sha256 = "1fg76pjn4h5w7fqmhzrmn1xz2brar48p02kf8gds9xayi6mxw6m6";
  };

  nativeBuildInputs = [ p7zip ];

  unpackPhase = ''
    runHook preUnpack

    echo "Extracting iso..."
    7z x "$src" sources/install.wim

    echo "Extracting font and license files..."
    mkdir -p fonts
    7z e sources/install.wim \
      Windows/{Fonts/"*".{ttf,ttc},System32/Licenses/neutral/"*"/"*"/license*.rtf} \
      -ofonts

    echo "Cleaning up..."
    rm -rf sources

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    fontDir="$out/share/fonts/truetype"
    licenseDir="$out/share/licenses/${pname}"

    install -d "$fontDir" "$licenseDir"

    echo "Installing fonts into '$fontDir'"
    find fonts -maxdepth 1 -type f \( -iname '*.ttf' -o -iname '*.ttc' \) \
      -execdir install -Dm444 '{}' "$fontDir/{}" \;

    echo "Installing license files into '$licenseDir'"
    find fonts -maxdepth 1 -type f -iname 'license*.rtf' \
      -execdir install -Dm444 '{}' "$licenseDir/{}" \;

    echo "Cleaning up temporary files"
    rm -rf fonts

    runHook postInstall
  '';

  passthru = {
    isoUrl = src.url;
    updateScript = {
      command = [ "${updateScriptDrv}/bin/update-ttf-ms-win11-auto" ];
    };
    updateScriptPackage = updateScriptDrv;
  };

  meta = {
    description = "Microsoft's TrueType fonts from Windows 11";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    platforms = lib.platforms.all;
    license = lib.licenses.unfree;
    longDescription = ''
      Microsoft ships a large collection of TrueType fonts with Windows 11.
      This derivation extracts those fonts from the publicly available Windows
      Enterprise evaluation image and installs them for use on Nix-based
      systems. Use of these fonts is subject to Microsoft's licensing terms.
    '';
  };
}
