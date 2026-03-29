{
  lib,
  stdenv,
  fetchFromGitHub,
  apple-sdk_26,
  darwinMinVersionHook,
  meson,
  ninja,
  pkg-config,
  python3,
  git,
  makeWrapper,
}:

let
  pname = "vmnet-helper";
  source = import ./source.nix;
in
stdenv.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchFromGitHub source.src;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    python3
    git
    makeWrapper
  ];

  buildInputs = [
    apple-sdk_26
    (darwinMinVersionHook "26.0")
  ];

  strictDeps = true;

  postPatch = ''
    substituteInPlace gen-version \
      --replace-fail '/usr/bin/env python3' '${lib.getExe python3}'
  '';

  postInstall = ''
            install -d "$out/libexec/${pname}"
            mv "$out/bin/vmnet-helper" "$out/libexec/${pname}/vmnet-helper-raw"

            install -Dm644 "$NIX_BUILD_TOP/source/entitlements.plist" "$out/share/${pname}/entitlements.plist"
            install -d "$out/share/${pname}"
        cat >"$out/libexec/${pname}/vmnet-helper-sign-and-run" <<'EOF'
    #!/usr/bin/env bash
    set -euo pipefail

    cache_root="''${XDG_CACHE_HOME:-$HOME/Library/Caches}/nix-conf-server/vmnet-helper-${source.version}"
    signed_helper="$cache_root/vmnet-helper"
    stamp_path="$cache_root/source-path"
    src_helper="@src_helper@"
    entitlements="@entitlements@"

        mkdir -p "$cache_root"

        if [[ ! -x $signed_helper || ! -f $stamp_path || $(cat "$stamp_path") != "$src_helper" ]]; then
          tmp_helper="$cache_root/vmnet-helper.tmp"
          cp "$src_helper" "$tmp_helper"
          chmod 755 "$tmp_helper"
          /usr/bin/codesign -f -s - --entitlements "$entitlements" "$tmp_helper" >/dev/null
          mv "$tmp_helper" "$signed_helper"
          printf '%s\n' "$src_helper" >"$stamp_path"
        fi

    exec "$signed_helper" "$@"
    EOF
        substituteInPlace "$out/libexec/${pname}/vmnet-helper-sign-and-run" \
          --replace-fail '@src_helper@' "$out/libexec/${pname}/vmnet-helper-raw" \
          --replace-fail '@entitlements@' "$out/share/${pname}/entitlements.plist"
        chmod 755 "$out/libexec/${pname}/vmnet-helper-sign-and-run"
            makeWrapper "$out/libexec/${pname}/vmnet-helper-sign-and-run" "$out/bin/vmnet-helper"

            cat >"$out/share/${pname}/README.nix" <<'EOF'
        This package ships a source-built vmnet-helper binary.

        The wrapper signs a per-user cached copy with the upstream entitlements on first run,
        because the Nix store itself is immutable.
        EOF
  '';

  passthru = {
    updateScript = [ ./update.py ];
  };

  meta = {
    description = "vmnet transport helper for macOS virtual machines";
    homepage = "https://github.com/nirs/vmnet-helper";
    license = lib.licenses.asl20;
    mainProgram = "vmnet-helper";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
