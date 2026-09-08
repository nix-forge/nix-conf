# Zen web fonts blocked by an imported filter list

Investigated on the Linux desktop on 2026-09-06 using Zen 1.21.15b and uBlock Origin 1.74.0.

## Cause

The WeatherNext page displayed fragments such as `an`, `zo`, `fa`, and `ch` where it should display icons. Its icons are text ligatures from Google Symbols. Blocking the font stylesheet leaves the icon names rendered in a fallback text font, with the names clipped by the icon containers. Its regular Google Sans Flex stylesheet was blocked too, changing text metrics and wrapping.

A fresh Zen profile rendered the page correctly. Adding the repository's managed browser preferences still passed. Copying only the live uBlock extension state into an isolated profile reproduced both reported screenshots. No cookies, passwords, browsing history, or other extensions' storage were copied.

The saved uBlock selection included this imported list:

```text
https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt
```

The list blocks third-party requests to `fonts.googleapis.com` and `fonts.gstatic.com`. It makes exceptions for some icon fonts, but its Google Symbols font-file exception cannot help when the preceding stylesheet request is blocked. The failure therefore affects other websites that depend on those services. [Filter-list source](https://github.com/yokoffing/filterlists/blob/main/block_third_party_fonts.txt).

The controlled experiment removed only this subscription through uBlock's own `applyFilterListSelection` and `reloadAllFilters` operations. Both fonts loaded, and the three card icons and button arrows rendered correctly. The other selected lists and the dynamic filtering rules were unchanged. [uBlock filter-list management implementation](https://github.com/gorhill/uBlock/blob/master/src/js/storage.js), [dashboard implementation](https://github.com/gorhill/uBlock/blob/master/src/js/3p-filters.js).

## Applied repair

Removed the imported subscription from the live Zen profile using the uBlock dashboard's delete-list and Apply changes controls. This removes it from both the selected and imported lists and saves the change through the extension. The custom-list count changed from seven to six. The other list selections, script/frame rules, tracking protection, downloadable-font validation, and font packages were retained.

Reloaded the existing WeatherNext tab. The button arrows and heading now render correctly in the user's running browser. Before and after screenshots from the isolated reproduction are [before](assets/zen-webfonts/before.png) and [after](assets/zen-webfonts/after.png).

The offending subscription was saved in the browser profile, not declared in the Nix configuration. The shared Nix configuration already defaults to uBlock's stock lists and contains no font-blocking subscription. No site-specific stylesheet, font alias, allow rule, or site exception was added.

This repair uses uBlock's normal cross-platform configuration. A Darwin Zen profile with the same imported list needs that subscription removed there too. The Mac was unavailable, so this investigation does not claim to have changed its saved extension state.

## Regression check

The browser rendering test now has a `webfonts` suite. It serves a small independent page on loopback, requests third-party text and icon stylesheets, and checks actual font loading plus icon ligature width. It does not load WeatherNext or add an exception for it.

Run in a graphical session with Python containing Selenium and Pillow, an installed Zen binary, and geckodriver:

```sh
python tests/browsers/check_font_rendering.py \
  --suite webfonts --headed \
  --browser "$(command -v zen-beta)" \
  --geckodriver "$(command -v geckodriver)" \
  --ublock-xpi ~/.config/zen/default/extensions/uBlock0@raymondhill.net.xpi \
  --output /tmp/zen-webfont-check
```

To reproduce the failure in that isolated test profile, add:

```text
--filter-list https://raw.githubusercontent.com/yokoffing/filterlists/main/block_third_party_fonts.txt
```

The bad-list run fails both font-loading checks and renders `animation` about 300.5 CSS pixels wide instead of one 64-pixel icon. The normal uBlock run passes. The existing digit regression also passes all 160 cases across eight families and two numeric styles. [Recorded results](assets/zen-webfonts/results.json). No live profile is changed by this regression command.

Some console warnings on the original page concern intentionally blocked advertising/tracking requests or empty media sources. They do not explain the font failure. The isolated extension-state copy also produced quota initialization warnings because only that extension's storage was copied; those warnings were not treated as evidence of damage to the live profile.
