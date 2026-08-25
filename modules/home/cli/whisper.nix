{ lib, pkgs, ... }:
let
  openai-whisper = pkgs.openai-whisper.overridePythonAttrs (old: {
    # A desktop transcription tool should not silently pull a multi-gigabyte
    # CUDA runtime into every Home Manager generation. Keep GPU acceleration an
    # explicit, host-specific choice; CPU inference is portable and suitable
    # for the general CLI profile.
    dependencies = lib.filter (package: lib.getName package != "torch") old.dependencies ++ [
      pkgs.python3Packages.torchWithoutCuda
    ];
  });
in
{
  home.packages = [
    (openai-whisper.overridePythonAttrs (_old: {
      doCheck = false;
    }))
  ];
}
