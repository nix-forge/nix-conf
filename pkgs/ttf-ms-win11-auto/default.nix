{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:

let
  pname = "ttf-ms-win11-auto";
  # Managed by update.py
  version = "10.0.26100.1742";

  src = fetchurl {
    url = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso";
    hash = "sha256-dNaW5mb2luk9toWoXJS/v8wHlt/Pii4uLiyQilToKUk=";
  };

  # Managed by update.py
  fontFiles = [
    "arial.ttf"
    "arialbd.ttf"
    "ariali.ttf"
    "arialbi.ttf"
    "ariblk.ttf"
    "bahnschrift.ttf"
    "calibri.ttf"
    "calibrib.ttf"
    "calibrii.ttf"
    "calibriz.ttf"
    "calibril.ttf"
    "calibrili.ttf"
    "cambria.ttc"
    "cambriab.ttf"
    "cambriai.ttf"
    "cambriaz.ttf"
    "Candara.ttf"
    "Candarab.ttf"
    "Candarai.ttf"
    "Candaraz.ttf"
    "Candaral.ttf"
    "Candarali.ttf"
    "comic.ttf"
    "comicbd.ttf"
    "comici.ttf"
    "comicz.ttf"
    "consola.ttf"
    "consolab.ttf"
    "consolai.ttf"
    "consolaz.ttf"
    "constan.ttf"
    "constanb.ttf"
    "constani.ttf"
    "constanz.ttf"
    "corbel.ttf"
    "corbelb.ttf"
    "corbeli.ttf"
    "corbelz.ttf"
    "corbell.ttf"
    "corbelli.ttf"
    "cour.ttf"
    "courbd.ttf"
    "couri.ttf"
    "courbi.ttf"
    "framd.ttf"
    "framdit.ttf"
    "Gabriola.ttf"
    "georgia.ttf"
    "georgiab.ttf"
    "georgiai.ttf"
    "georgiaz.ttf"
    "impact.ttf"
    "Inkfree.ttf"
    "l_10646.ttf"
    "lucon.ttf"
    "marlett.ttf"
    "micross.ttf"
    "pala.ttf"
    "palab.ttf"
    "palai.ttf"
    "palabi.ttf"
    "segmdl2.ttf"
    "SegoeIcons.ttf"
    "segoepr.ttf"
    "segoeprb.ttf"
    "segoesc.ttf"
    "segoescb.ttf"
    "segoeui.ttf"
    "segoeuib.ttf"
    "segoeuii.ttf"
    "segoeuiz.ttf"
    "segoeuil.ttf"
    "seguili.ttf"
    "segoeuisl.ttf"
    "seguisli.ttf"
    "seguibl.ttf"
    "seguibli.ttf"
    "seguiemj.ttf"
    "seguihis.ttf"
    "seguisb.ttf"
    "seguisbi.ttf"
    "seguisym.ttf"
    "SegUIVar.ttf"
    "SitkaVF.ttf"
    "SitkaVF-Italic.ttf"
    "sylfaen.ttf"
    "symbol.ttf"
    "tahoma.ttf"
    "tahomabd.ttf"
    "times.ttf"
    "timesbd.ttf"
    "timesi.ttf"
    "timesbi.ttf"
    "trebuc.ttf"
    "trebucbd.ttf"
    "trebucit.ttf"
    "trebucbi.ttf"
    "verdana.ttf"
    "verdanab.ttf"
    "verdanai.ttf"
    "verdanaz.ttf"
    "webdings.ttf"
    "wingding.ttf"
    "msgothic.ttc"
    "YuGothR.ttc"
    "YuGothB.ttc"
    "YuGothM.ttc"
    "YuGothL.ttc"
    "malgun.ttf"
    "malgunbd.ttf"
    "malgunsl.ttf"
    "javatext.ttf"
    "himalaya.ttf"
    "ntailu.ttf"
    "ntailub.ttf"
    "phagspa.ttf"
    "phagspab.ttf"
    "taile.ttf"
    "taileb.ttf"
    "msyi.ttf"
    "monbaiti.ttf"
    "mmrtext.ttf"
    "mmrtextb.ttf"
    "Nirmala.ttc"
    "LeelawUI.ttf"
    "LeelaUIb.ttf"
    "LeelUIsl.ttf"
    "simsun.ttc"
    "simsunb.ttf"
    "msyh.ttc"
    "msyhbd.ttc"
    "msyhl.ttc"
    "msjh.ttc"
    "msjhbd.ttc"
    "msjhl.ttc"
    "mingliub.ttc"
    "ebrima.ttf"
    "ebrimabd.ttf"
    "gadugi.ttf"
    "gadugib.ttf"
    "mvboli.ttf"
  ];

  wimTargets = (map (font: "Windows/Fonts/${font}") fontFiles) ++ [
    "Windows/System32/Licenses/neutral/*/*/license.rtf"
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname version src;

  nativeBuildInputs = [ _7zz ];
  dontUnpack = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    workdir="$PWD/work"
    isodir="$workdir/iso"
    extracteddir="$workdir/extracted"
    mkdir -p "$isodir" "$extracteddir"

    7zz x -y -o"$isodir" "$src" 'sources/install.wim' >/dev/null

    7zz e -y -o"$extracteddir" "$isodir/sources/install.wim" \
      ${lib.concatStringsSep " " (map lib.escapeShellArg wimTargets)} >/dev/null

    missing=()
    for font in ${lib.concatStringsSep " " (map lib.escapeShellArg fontFiles)}; do
      if [ ! -f "$extracteddir/$font" ]; then
        missing+=("$font")
      fi
    done

    if [ "''${#missing[@]}" -ne 0 ]; then
      printf 'Missing expected fonts from install.wim:\n' >&2
      printf '  %s\n' "''${missing[@]}" >&2
      exit 1
    fi

    if [ ! -f "$extracteddir/license.rtf" ]; then
      echo "Missing license.rtf in install.wim extraction output" >&2
      exit 1
    fi

    install -d "$out/share/fonts/truetype"
    for font in ${lib.concatStringsSep " " (map lib.escapeShellArg fontFiles)}; do
      install -m444 "$extracteddir/$font" "$out/share/fonts/truetype/$font"
    done

    install -d "$out/share/licenses/${finalAttrs.pname}"
    install -m444 "$extracteddir/license.rtf" "$out/share/licenses/${finalAttrs.pname}/license.rtf"

    runHook postInstall
  '';

  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "Microsoft Windows 11 TrueType fonts extracted from the Enterprise Evaluation ISO";
    homepage = "https://www.microsoft.com/typography/fonts/product.aspx?PID=164";
    downloadPage = "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise";
    changelog = "https://aur.archlinux.org/cgit/aur.git/log/PKGBUILD?h=ttf-ms-win11-auto";
    platforms = lib.platforms.all;
    license = lib.licenses.unfree;
    priority = 5;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
