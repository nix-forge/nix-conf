_: {
  reason = "Combined patchelf interpreter/RPATH rewriting maps NVIDIA executables' dynamic section read-only and crashes the ELF loader.";
  upstream = "https://github.com/NixOS/nixpkgs/issues/576412";
  removal = "The upstream NVIDIA builder patches the interpreter and RPATH without overlapping read-only LOAD mappings, and nvidia-smi --help runs without this repair.";
  reviewedRevision = "02c087f3fe673c9e317f206a627cb6b910336dbe";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      # Start from upstream's retained originals: rewriting the already broken
      # binaries cannot restore their original segment layout. Separate the two
      # edits while retaining this derivation's exact libraries and interpreter.
      postInstall = (if (old.postInstall or null) == null then "" else old.postInstall) + ''
        for program in nvidia-cuda-mps-control nvidia-cuda-mps-server nvidia-smi nvidia-debugdump nvidia-powerd; do
          if [ -f "$bin/origBin/$program" ]; then
            install -m755 "$bin/origBin/$program" "$bin/bin/$program"
            patchelf --set-rpath "$out/lib:$libPath" "$bin/bin/$program"
            patchelf --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" "$bin/bin/$program"
          fi
        done
      '';
      doInstallCheck = true;
      # Help exercises the real dynamic loader without requiring a GPU in the
      # build sandbox. Deployment separately checks the live NVML query.
      postInstallCheck =
        (if (old.postInstallCheck or null) == null then "" else old.postInstallCheck)
        + ''
          "$bin/bin/nvidia-smi" --help > /dev/null
        '';
    });
}
