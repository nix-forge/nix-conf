{ lib, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  programs.helium.flags = [
    "--no-first-run"
    "--no-default-browser-check"
    "--disable-features=ChromeWhatsNewUI,OptimizationGuideModelDownloading,OptimizationHintsFetching,OptimizationTargetPrediction"
  ]
  ++ lib.optionals isLinux [
    "--ozone-platform-hint=auto"
    "--enable-features=TouchpadOverscrollHistoryNavigation,VaapiVideoDecodeLinuxGL,VaapiVideoEncoder"
    "--ignore-gpu-blocklist"
    "--enable-zero-copy"
  ];
}
