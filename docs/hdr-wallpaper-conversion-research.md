# HDR wallpaper conversion research

## Decision

Keep `awww` for rotating wallpapers, but treat it as an 8-bit SDR renderer. Add
a conversion stage for EXR and every decoded source that cannot safely reach its
8-bit `wl_shm` layer surface unchanged. The result should be a tone-mapped,
sRGB PNG. This is the right quality target for the present wallpaper stack.

Do not describe the result as an HDR wallpaper. `awww` cannot present one. A
4K source may still be worth keeping in the cache, but the current `SUNSHINE`
output is 2562x1656, so it cannot show 3840x2160 detail. Do not upscale smaller
images just to meet a 4K label.

## What the display stack can do

Hyprland 0.55 has 10-bit output and color-management monitor settings. Its
`hdr` and `hdredid` presets use a PQ transfer function, but the upstream manual
calls both experimental. It also warns that Hyprland-owned colors are not
10-bit and that some screen capture applications do not work with 10-bit
output. This is usable for careful, physical-monitor testing, not a basis for
claiming an HDR wallpaper pipeline. [Hyprland monitor documentation](https://wiki.hypr.land/0.55.0/Configuring/Basics/Monitors/)

The deployed wallpaper client is more limiting than the compositor. Nixpkgs
pins `awww` 0.12.1. It enables the Rust `image` decoders for EXR and Radiance
HDR, although its README does not advertise those formats. [Decoder features](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/client/Cargo.toml) [Advertised input list](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/README.md#L65)

After decode, however, `awww` unconditionally turns a still into `rgb8` or
`rgba8`. [Raster conversion](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/client/src/imgproc.rs) Its daemon supports only RGB/BGR 888 and
ARGB/ABGR 8888 Wayland shared-memory buffers. [Pixel formats](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/common/src/ipc/types.rs) [Wayland mapping](https://codeberg.org/LGFae/awww/src/tag/v0.12.1/daemon/src/wallpaper/bump_pool.rs#L269)

Thus feeding `awww` EXR, 16-bit PNG/TIFF, HDR JXL, or HDR AVIF/HEIF loses
precision without a controlled display transform. A naïve conversion may also
clip scene-linear highlights. Convert first, then give `awww` an ordinary SDR
PNG.

## Recommended conversion path

Use OpenImageIO's `oiiotool` with an explicit OCIO configuration. It keeps the
scene-referred image in floating point while it applies the display transform,
has a real color-space conversion operation, and its resize operation has
high-quality defaults. [Color-management commands](https://openimageio.readthedocs.io/en/v3.1.12.1/oiiotool.html#oiiotool-color-management) [Resize and HDR highlight compensation](https://openimageio.readthedocs.io/en/v3.1.12.1/oiiotool.html#cmdoption-oiiotool-fit)

1. Inspect the file and metadata, including all EXR parts. Only use the beauty
   RGB or RGBA image. Reject deep EXRs, missing RGB, nonfinite pixels, and
   malformed images. Do not choose a transform from the filename extension.
2. Determine the input color space from trustworthy embedded metadata or the
   source contract. If it is unknown, reject it for automatic conversion rather
   than guessing whether it is linear sRGB, ACEScg, or a display-referred image.
3. Use that input space with an OCIO display/view transform that tone maps to
   sRGB. `oiiotool --ociodisplay` applies the named OCIO display transform and
   accepts an explicit input space. [OCIO display transform](https://openimageio.readthedocs.io/en/v3.1.12.1/oiiotool.html#cmdoption-oiiotool-ociodisplay)
4. Resize only when the image exceeds the configured target. Keep the original
   aspect ratio and do not upscale. For a high-contrast HDR source, use
   `highlightcomp=1` with the resize operation. OpenImageIO says this surrounds
   the filter with range compression and expansion to reduce HDR ringing.
5. Emit lossless sRGB PNG. The final `uint8` quantization is intentional,
   because `awww` will make it anyway. Enable dither when reducing float or
   half data to 8-bit to hide smooth-gradient banding. [Dithering](https://openimageio.readthedocs.io/en/v3.1.12.1/oiiotool.html#cmdoption-oiiotool-dither)

The exact color-space and display/view names are installation-specific. List
them during activation with `oiiotool --colorconfiginfo`; never bake in a name
that an installed OCIO config does not provide. A representative command shape
is:

```sh
oiiotool --colorconfig "$OCIO" input.exr \
  --ociodisplay:from="$input_space" "$display" "$view" \
  --fit:filter=lanczos3:highlightcomp=1 2562x1656 \
  -d uint8 --dither -o wallpaper.png
```

Use `3840x2160` only for a physical 4K output or a separately retained source
rendition. For the configured virtual desktop, use its actual 2562x1656 size.

## Scope of automatic conversion

Route files by decoder inspection and pixel characteristics, not just MIME type
or suffix. The conversion path should cover EXR, Radiance HDR, high-bit-depth
PNG and TIFF, and HDR variants of AVIF, HEIF, and JPEG XL when the installed
decoder can identify their transfer function and color primaries. Keep normal
8-bit sRGB JPEG, PNG, WebP, AVIF, TIFF, and JXL unchanged when `awww` handles
them. Preserve the original alongside the generated PNG and write a sidecar
with source URL, SHA-256, dimensions, input color space, OCIO config digest,
display/view, and conversion command version.

This deliberately does not promise conversion for camera RAW, layered PSD, deep
or multipart EXR, vector images, video, or files with unknown color encoding.
Those need a source-specific artistic choice. Silent conversion would produce a
plausible but wrong wallpaper.
