# Hyprland crash on September 5, 2026

Hyprland crashed at 23:17:31 PDT while a temporary Zen browser used by the
Codex task "Troubleshoot YouTube HDR in Zen" was closing. The task completed
its fullscreen playback probe at the same time. Codex lost its Wayland
connection two seconds later, along with the wallpaper daemon, portals,
and other applications. The watchdog restarted Hyprland in safe mode.

The crash was in Hyprland's client teardown, not Codex's application process.
The inspected kernel journal contained no NVIDIA Xid or GPU reset at that time.

## Evidence

- Desktop crash report: `~/.cache/hyprland/hyprlandCrashReport2247.txt`.
- Original executable: Hyprland revision
  `ee0409623e2d6a683374b39a32e0ac3d087841aa`.
- The original stack was `wl_client_destroy` →
  `CWLSubsurfaceResource::destroy` → `CSubsurface::onUnmap` →
  `damageLastArea` → `coordsGlobal` → `posRelativeToParent`.
- The faulting instruction in `posRelativeToParent+0x228` dereferenced a null
  parent surface at offset `0x608`.
- A separate nested compositor reproduced the same stack and instruction
  after a mapped subsurface's parent surface was destroyed first.

The source is [Subcompositor.cpp at the pinned revision](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/protocols/core/Subcompositor.cpp).
Both `posRelativeToParent` and `t1Parent` lock a weak parent reference, then
dereference it without checking whether the parent still exists.

## Fix and verification

The NixOS Hyprland package now applies a two-line patch that stops each parent
walk when its weak reference has expired. The compositor and portal retain
their pinned upstream inputs. No browser acceleration or HDR settings are
disabled by this fix.

`tests/hyprland/check-subsurface-teardown.sh` compiles a Wayland client and
starts a separate nested compositor. Its short private runtime directory
isolates its sockets and systemd activation environment. Only a DRM render
node is allowed, and the script checks that every output belongs to the
nested Wayland backend before running the client.

The client waits for a frame callback before destroying a parent surface and
then its child subsurface. This exercises teardown of a rendered surface;
merely creating resources and immediately destroying them did not reproduce
the crash. A second scenario disconnects the client with its surfaces intact.

With the dependencies listed in the script available, run it within a Wayland
session and pass the compositor binary to test:

```sh
bash tests/hyprland/check-subsurface-teardown.sh /path/to/Hyprland
```

Results before deployment:

- Original binary: fails on the first parent-first teardown, with the original
  crash stack.
- Patched binary: passes five parent-first teardowns and five client
  disconnects. The compositor remains responsive after each disconnect.
- ShellCheck and `git diff --check`: pass.
- `just desktop-build`: full desktop build and dry activation pass on
  `desktop`.

The deployment snapshot includes the desktop checkout's pending screenshot
and font fixes, so installing the compositor repair also preserves that work.

Deployment and recovery completed with system closure
`/nix/store/k498vm5yyg8khb5nkjhyrfzb7842gnhc-nixos-system-desktop-26.11.20260826.9fbb54b`.
The running compositor uses the patched `ksiwia49q69bszc84j4v45aasin1lbvi`
package and has no `--safe-mode` flag. The display is 3840×2160 at 240.016 Hz
with scale 1.5. Codex, Noctalia, wallpaper, PipeWire, and the Hyprland portal
are running; configuration errors and failed system/user units are empty.

The existing `/tmp/zen-hdr-probe.py` playback-and-close probe was rerun in a
temporary browser profile through `hyprland-zen-crash-verification.service`.
It exited successfully in 20.854 seconds, and Hyprland retained the same PID
and instance throughout. The probe's temporary HDR preferences were not
installed into the user's regular browser profile.
