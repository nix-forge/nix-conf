{ pkgs, ... }: {
  reason = "The AudioMuse-AI Navidrome plugin grants HTTP access to every host instead of this deployment's loopback API.";
  upstream = "https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/tag/v10";
  removal = "The packaged plugin manifest limits HTTP access to 127.0.0.1; until then this fix also verifies that the permission does not silently broaden or change shape.";
  reviewedRevision = "8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe";
  inputPath = [ "nixpkgs" ];
  packageName = "navidromePlugins.audiomuseai";
  affectedVersions = null;
  apply =
    package:
    package.overrideAttrs (
      _finalAttrs: previousAttrs: {
        src = pkgs.runCommand "audiomuseai-plugin-loopback-source" { nativeBuildInputs = [ pkgs.jq ]; } ''
          cp -R ${previousAttrs.src} "$out"
          chmod -R u+w "$out"
          required_hosts="$(${pkgs.jq}/bin/jq -c '.permissions.http.requiredHosts' "$out/manifest.json")"
          if [ "$required_hosts" = '["*"]' ]; then
            temporary_manifest="$(mktemp)"
            ${pkgs.jq}/bin/jq '.permissions.http.requiredHosts = ["127.0.0.1"]' \
              "$out/manifest.json" > "$temporary_manifest"
            mv "$temporary_manifest" "$out/manifest.json"
          elif [ "$required_hosts" != '["127.0.0.1"]' ]; then
            printf 'Unexpected AudioMuse-AI HTTP requiredHosts: %s\n' "$required_hosts" >&2
            exit 1
          fi
        '';
        nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.unzip ];
        postInstall = (previousAttrs.postInstall or "") + ''
          packed_required_hosts="$(
            ${pkgs.unzip}/bin/unzip -p "$out/share/audiomuseai.ndp" manifest.json \
              | ${pkgs.jq}/bin/jq -c '.permissions.http.requiredHosts'
          )"
          if [ "$packed_required_hosts" != '["127.0.0.1"]' ]; then
            printf 'Packed AudioMuse-AI HTTP requiredHosts are unsafe: %s\n' \
              "$packed_required_hosts" >&2
            exit 1
          fi
        '';
      }
    );
}
