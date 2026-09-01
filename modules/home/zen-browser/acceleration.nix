{ lib, myLib, ... }: {
  # Zen tracks Firefox closely.  Keep this limited to decoder preferences that
  # Firefox's current NVIDIA VA-API implementation needs; WebRender and GPU
  # selection remain automatic so the same module works on Mesa-only systems.
  programs.zen-browser.profiles.default.extraConfig = lib.mkAfter (
    myLib.firefox.toUserJS {
      # Firefox 137+ otherwise keeps the Linux hardware-decoder path behind a
      # conservative runtime gate.  The host still has to pass its own VA-API
      # probe; this does not substitute a software decoder for a hardware one.
      "media.hardware-video-decoding.force-enabled" = true;

      # Keep FFmpeg in the restricted RDD process.  Do not set
      # MOZ_DISABLE_RDD_SANDBOX: reducing that sandbox would be an unacceptable
      # tradeoff merely to accommodate a GPU driver.
      "media.rdd-ffmpeg.enabled" = true;
    }
  );
}
