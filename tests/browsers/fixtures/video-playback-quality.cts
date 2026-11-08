// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe() {
  const v = document.querySelector("video");
  if (!v) throw new Error("Video fixture missing");
  const q = v.getVideoPlaybackQuality();
  return {
    frames: q.totalVideoFrames,
    dropped: q.droppedVideoFrames,
    fullscreen: !!document.fullscreenElement,
    paused: v.paused,
    error: v.error?.message ?? null,
    width: v.videoWidth,
    height: v.videoHeight,
  };
};
