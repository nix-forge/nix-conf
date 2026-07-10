{ pkgs, ... }:
let
  openai-whisper = pkgs.openai-whisper.override { ffmpeg-headless = pkgs.ffmpeg; };
in
{
  home.packages = [
    (openai-whisper.overridePythonAttrs (_old: {
      doCheck = false;
    }))
  ];
}
