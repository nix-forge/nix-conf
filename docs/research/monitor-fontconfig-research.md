# Font rendering on the ASUS PG32UCWM

Research date: 2026-09-06

## Recommendation

Keep the current grayscale antialiasing and slight hinting. The live desktop already has appropriate Fontconfig defaults for its mixed Wayland applications at 150% scale. Research did not establish a font-rendering defect or a general improvement that would justify changing them.

The panel supports conventional RGB subpixel rendering. That makes `rgb` a valid option for a deliberate application-specific comparison, but it does not make grayscale a misconfiguration. Visual preference between the two requires viewing the actual panel at normal reading distance.

## Panel geometry

ASUS identifies the PG32UCWM as a true RGB stripe OLED. Its product page explicitly says it removes the white subpixel used in earlier WOLED panels, and describes vertically shaped red, green, and blue stripes arranged across each pixel. A four-subpixel RGWB assumption is incorrect for this model. The specification page still calls the panel WOLED, so that label alone is insufficient to determine geometry. Sources: [ASUS product description](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/), [ASUS specifications](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/spec/).

For its normal landscape orientation, the corresponding Fontconfig geometry is `rgb`. The `vrgb` value refers to color subpixels stacked vertically, not the shape of each stripe. `bgr` reverses the horizontal order and has no supporting hardware evidence here. Fontconfig exposes `unknown`, `rgb`, `bgr`, `vrgb`, `vbgr`, and `none`. Sources: [Fontconfig manual](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html), [FreeType subpixel geometry](https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html).

ASUS specifies a 3840x2160 raster, a 696.58 by 391.82 mm viewing area, and a 0.1814 mm pixel pitch. Calculating `25.4 / 0.1814` gives about 140 physical pixels per inch. At 1.5 scale, the logical desktop is 2560x1440. The scale changes application sizing; it does not change physical pixel density. Source: [ASUS specifications](https://rog.asus.com/monitors/27-to-31-5-inches/rog-swift-oled-pg32ucwm/spec/).

## Why retain the current settings

| Setting | Current value | Assessment |
| --- | --- | --- |
| Antialiasing | Enabled | Keep smooth glyph edges. |
| Subpixel rendering | `none`, grayscale | Appropriate default across the current application mix. |
| Hinting | Enabled, `hintslight` | Reasonable balance between letter shape and pixel alignment. |
| Forced autohinting | Disabled | No observed font-specific defect requiring an override. |

FreeType describes light hinting as snapping outlines vertically while preserving horizontal spacing more closely. It can also be combined with LCD rendering, so hinting and subpixel antialiasing are separate decisions. Retaining slight hinting at this density is a judgment based on that behavior, rather than a monitor-specific vendor requirement. Source: [FreeType glyph loading and rendering](https://freetype.org/freetype2/docs/reference/ft2-glyph_retrieval.html#ft_load_target_xxx).

GTK 4's renderer uses grayscale antialiasing and ignores `gtk-xft-rgba`. A global RGB switch would therefore have no effect on these applications. GTK's rendering discussion also distinguishes subpixel positioning, which improves spacing, from colored subpixel antialiasing. Sources: [GTK setting documentation](https://docs.gtk.org/gtk4/property.Settings.gtk-xft-rgba.html), [GTK developers on fractional scales and hinting](https://blogs.gnome.org/gtk/2024/03/07/on-fractional-scales-fonts-and-hinting/).

Fractional scaling alone does not require blurry text or prohibit RGB rendering. Modern GTK renderers handle device-pixel placement directly, whereas older paths may render at an integer scale and then downsample. My inference is that grayscale is a sensible common default when applications use different scaling paths. A resampled RGB mask cannot be assumed to retain alignment with the display's physical stripes. Sources: [GTK rendering explanation](https://blogs.gnome.org/gtk/2024/03/07/on-fractional-scales-fonts-and-hinting/), [FreeType's dependence on subpixel geometry](https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html).

If an application-specific RGB trial is later warranted, use `lcddefault` filtering initially. FreeType's default filter balances colors, while disabling filtering can produce strong color fringes. This filter affects LCD rendering, so changing it has no benefit for grayscale text. Source: [FreeType LCD filters](https://freetype.org/freetype2/docs/reference/ft2-lcd_rendering.html#ft_lcdfilter).

## Local verification

The desktop audit recorded these live values on the research date:

- `hyprctl monitors` identified the PG32UCWM on `DP-4`, at 3840x2160 and 240.016 Hz, scale 1.5, transform 0.
- `fc-match` selected Inter, Literata, and MonaspiceNe for the primary text families. Each reported `rgba=5`, `hintstyle=1`, `hinting=true`, `autohint=false`, `antialias=true`, and `embeddedbitmap=true`. Fontconfig defines the numeric geometry and hint-style values as `none` and `hintslight`.
- The same text families and rendering values resolved with `XDG_CONFIG_HOME=/nonexistent` and `XDG_DATA_HOME=/nonexistent`.
- `gsettings` reported `org.gnome.desktop.interface` font antialiasing as `grayscale` and font hinting as `slight`. The inspected GTK configuration files contained no `gtk-xft` overrides.
- Evaluation of `nixosConfigurations.desktop` agreed with the live rendering settings, and Home Manager Fontconfig support was enabled. The evaluated bitmap options were enabled, so values in one source module should not be mistaken for the effective configuration.

X11 resources were not verified because the X display connection was unavailable. This audit added documentation only and required no system rebuild.

These observations establish the active mode and defaults. They do not measure subjective sharpness or prove that every toolkit uses every Fontconfig setting. The research recommends no monitor-driven Fontconfig change. Existing font-family and emoji policies should be assessed separately from panel geometry.
