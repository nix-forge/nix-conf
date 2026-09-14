# Themes and font rendering

The full configuration uses Stylix to share appearance settings across applications.
Application modules own installation and behavior; theme modules own colors,
fonts, and generated styling. This separation lets you change appearance without
starting an application you did not select.

This is an advanced walkthrough of the existing host setup, not a standalone
import recipe. The shared appearance module depends on the framework and package
collection. Start with the smaller recipes if your configuration does not use
those inputs.

## Choose a scheme

In an existing nix-conf host's local configuration:

```nix
{
  appearance.theme = "catppuccin-mocha";
}
```

The current choices include `carbon-neon`, `carbon-neon-oled`,
`catppuccin-mocha`, and `gruvbox-dark-medium`. Attached homes inherit the host's
selection unless they override it. Build the host configuration before applying
it; use the repository's host-specific commands and build placement rules.

The [theming reference](https://github.com/nix-forge/nix-conf/blob/main/docs/theming.md)
explains individual targets and how to disable custom styling. It also links the
source for application-specific decisions.

## Choose roles before collecting fonts

The full setup assigns interface, serif, monospace, and emoji roles separately.
The optional design library is another decision. In a home that already imports
the repository's font module, use `typography.designLibrary = "none";` to skip
the large design collection while retaining required fonts.

These existing renderer captures show the same multilingual sample through Pango
and Qt. They are recorded font-test output, not screenshots of a newly validated
desktop or proof of every application's behavior.

![Pango rendering of digits, accented Latin, Arabic, Japanese, and an emoji](../assets/font-implementation/pango.png)

Pango sample. Digits, text shaping, CJK fallback, and emoji share one line.

![Qt rendering of the same multilingual sample](../assets/font-implementation/qt.png)

Qt sample. Comparing actual application toolkits catches differences that an
installed-font inventory alone cannot establish.

See the [font guide and recorded results](https://github.com/nix-forge/nix-conf/blob/main/docs/font-configuration.md)
for the selected families, provenance, checks, and platform differences. Some
optional font packages have separate upstream licensing requirements. The small
public starter requires none of them.
