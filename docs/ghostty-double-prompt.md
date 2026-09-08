# Ghostty 1.3.1 duplicate Bash prompt

Opening Ghostty with ble.sh produces two prompts before any keyboard input.
Ghostty's `OSC 133;A` marker can move the cursor to a new line without updating
ble.sh's cursor tracking. A minimal Bash prompt reproduces it without Starship,
Atuin, or the other shell plugins. Removing Home Manager's second integration
load does not fix it.

The Ghostty module backports
[upstream commit b1ad24e](https://github.com/ghostty-org/ghostty/commit/b1ad24e24f3c04d854ed2c516fd0b947cf800420).
It emits the nonmoving `OSC 133;P` marker when ble.sh is loaded. The patch applies
to a separate copy of the package's Bash integration, leaving the signed macOS
app intact. Home Manager loads the copy before `ble-attach`. Automatic injection
is disabled because it would reload the bundled, unpatched hook after `.bashrc`.
The normal integration features remain enabled.

The workaround applies to version 1.3.1 with Bash enabled. Remove the backport
when the pinned release includes the upstream fix.

## Verification

`tests/terminals/check_ghostty_prompt.py` starts Ghostty on a private Xvfb server
with a temporary home. It reads Ghostty's exported screen text. The original
configuration fails with two prompts; the corrected full Bash configuration
passes idle startup, continued idle, output without a trailing newline, and
Ctrl-L redraw. The test needs Linux, Ghostty, Xvfb, Python, and xdotool.

Build only the generated Bash configuration on the desktop, then test it:

```bash
bashrc=$(nix build --no-link --print-out-paths \
  'path:.#nixosConfigurations.desktop.config.home-manager.users.ianmh.home.file.".bashrc".source')
python3 tests/terminals/check_ghostty_prompt.py \
  --bashrc "$bashrc" --shell-integration none \
  --starship-config "$HOME/.config/starship.toml"
```

Darwin's generated startup code and Ghostty settings were evaluated, and its
startup code passed `bash -n`. The Mac was unreachable over SSH, so activation
and a native macOS window check remain outstanding. From this checkout on the
Mac, apply the configuration and open a new Ghostty window:

```bash
just darwin-switch macbook-pro-m4
```
