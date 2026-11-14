_: {
  reason = "nixos-anywhere disables SSH host-key verification before parsing caller options.";
  upstream = "https://github.com/nix-community/nixos-anywhere/blob/da83557d8b0bce57a52371b888ffd6d58724e55c/src/nixos-anywhere.sh";
  removal = "The pinned installer verifies SSH host keys by default or accepts an effective caller override.";
  reviewedRevision = "b6be7b277b468d55082584441cbef1fed8530eb3";
  inputPath = [ "nixos-anywhere" ];
  apply =
    package:
    package.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/nixos-anywhere.sh \
          --replace-fail 'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere" "-o" "UserKnownHostsFile=/dev/null" "-o" "StrictHostKeyChecking=no")' \
            'declare -a sshArgs=("-o" "IdentitiesOnly=yes" "-i" "$tempDir/nixos-anywhere")'
      '';
    });
}
