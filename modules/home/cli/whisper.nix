{ pkgs, ... }:
{
  home.packages = [
    (pkgs.openai-whisper.overridePythonAttrs (old: {
      doCheck = false;
    }))
  ];
}
