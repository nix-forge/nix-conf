// oxlint-disable-next-line unicorn/require-module-specifiers -- erased module marker isolates standalone probe declarations.
export type {};
module.exports = function browserProbe(
  samples: Array<{ text: string; width: number; code: string }>,
) {
  const canvas = document.createElement("canvas");
  canvas.width = 96;
  canvas.height = 96;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) throw new Error("Canvas 2D context unavailable");
  ctx.font = "48px AppleTest";
  ctx.fillStyle = "#ddd";
  const failures = [];
  let colored = 0;
  for (const sample of samples) {
    ctx.clearRect(0, 0, 96, 96);
    const width = ctx.measureText(sample.text).width;
    ctx.fillText(sample.text, 8, 64);
    const pixels = ctx.getImageData(0, 0, 96, 96).data;
    let visible = 0,
      color = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      if ((pixels[i + 3] ?? 0) > 32) {
        visible++;
        if (
          Math.max(pixels[i] ?? 0, pixels[i + 1] ?? 0, pixels[i + 2] ?? 0) -
            Math.min(pixels[i] ?? 0, pixels[i + 1] ?? 0, pixels[i + 2] ?? 0) >
          35
        )
          color++;
      }
    }
    if (color > 10) colored++;
    if (Math.abs(width - sample.width) > 0.1 || visible < 10)
      failures.push({
        code: sample.code,
        width,
        expected: sample.width,
        visible,
      });
  }
  document.body.style.cssText =
    "background:#202124;color:#eee;padding:28px;font:18px sans-serif";
  document.body.innerHTML =
    "<h1>Apple Color Emoji · installed Linux font</h1>" +
    "<p>Versioned release: macos-26-20260722-484daf4e · downloaded bitmap fonts disabled</p>" +
    '<div style="font:48px AppleTest;line-height:1.6">' +
    "😀 😎 🥰 😭 🫩 🫪 🫯 🐱 🦊 🦋 🌻 🍎 🍕 🎉 ❤️<br>" +
    "👍🏻 👍🏽 👍🏿 👩🏽‍💻 👨🏻‍🚀 🧑🏿‍🚒 🫱🏻‍🫲🏼 🫱🏿‍🫲🏻<br>" +
    "👩🏻‍❤️‍💋‍👩🏿 🧑🏽‍🤝‍🧑🏻 👨‍👩‍👧‍👦 🏳️‍🌈 🇺🇸 🇯🇵 ♀️ ♂️ ⚕️ 🏴󠁧󠁢󠁳󠁣󠁴󠁿 1️⃣</div>" +
    "<p>Font artwork © Apple Inc. Linux conversion: samuelngs/apple-emoji-ttf.</p>";
  return {
    total: samples.length,
    failures,
    colored,
    localFontLoaded: document.fonts.check("48px AppleTest"),
  };
};
