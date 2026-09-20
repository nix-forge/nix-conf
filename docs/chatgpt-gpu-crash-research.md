# ChatGPT Linux GPU-process crash research

Reviewed 2026-09-17 after a freeze followed by a ChatGPT desktop crash. This
note records the evidence for the session and package configuration in
[`interactive-desktop.nix`](../homes/desktop/local/interactive-desktop.nix).

## Conclusion

The latest event was not another global out-of-memory kill. The local coredump
record shows ChatGPT's Chromium GPU process terminating with `SIGTRAP` while
using `--ozone-platform=wayland` and the NVIDIA render node. The same signal
pattern appears in several preceding records for the current Linux app build.
There was no corresponding kernel OOM report, cgroup OOM event, GPU reset, or
GPU fault in the current boot's logs. The coredump policy intentionally keeps
the full dump disabled, so the native stack cannot identify the exact failing
code path.

This is correlation, not proof that Wayland or NVIDIA caused the trap. The
configuration keeps native Wayland as the preferred path: the system/home
session exports Wayland-first toolkit variables, including `NIXOS_OZONE_WL=1`,
and the ChatGPT package wrapper consumes that inherited setting when a
Wayland display exists. The application desktop entry remains the upstream
entry and does not duplicate session policy. GPU acceleration remains enabled.

## Evidence and research

- The crash-time package was version `26.901.51231`. The package wrapper adds
  `--ozone-platform=wayland` when `NIXOS_OZONE_WL` and a Wayland display are
  present. The current desktop environment exports that variable globally;
  it is not hardcoded in the ChatGPT desktop entry.
  The package updater now tracks the newer official release `26.911.61220`;
  its release notes do not establish that this version fixes the observed GPU
  trap, so the update is a prudent maintenance improvement rather than proof
  of remediation.
- The latest coredump record and several records from the prior two days name
  ChatGPT's GPU child and contain the explicit native-Wayland switch. The
  latest record also names the NVIDIA render node. This pattern is more
  specific than the older incidents, where global memory exhaustion preceded
  the application exit.
- OpenAI's [Linux desktop documentation](https://learn.chatgpt.com/docs/linux/linux-app)
  describes the Linux app as a preview and says native Wayland support is
  experimental. It also documents XWayland as the normal compatibility path
  when available and gives `--ozone-platform=wayland` as the explicit native
  Wayland selection.
- Chromium's [Ozone overview](https://chromium.googlesource.com/chromium/src/+/main/docs/ozone_overview.md)
  documents `--ozone-platform` as the runtime platform selector and describes
  the Wayland backend as actively developed. The package wrapper therefore
  selects a documented Chromium backend rather than relying on an undocumented
  application-specific switch.

The decision is intentionally Wayland-first across the desktop. XWayland
remains installed only as a compatibility layer for applications that have no
usable native backend; it is not made the session default.

## Validation and limits

The investigation used systemd user-scope status, coredump metadata, kernel
logs, GPU render-node identification, resolver queries, the installed package
wrapper, and the official OpenAI and Chromium documentation above. The new
Nix check validates the Wayland-first session variables; the package contract
check validates the ChatGPT wrapper separately.

The change has not yet been activated or A/B tested. After activation, fully
quit ChatGPT and start it from the dock or application launcher so it inherits
the new session environment. If the crash recurs, the next useful comparison is a
temporary diagnostic launch with native Wayland but `--disable-gpu`; that
distinguishes the Wayland windowing path from the accelerated GPU path without
changing the normal configuration. An upstream report should include the app
version, GPU driver, compositor, launch flags, and crash metadata, with
account and host-specific paths removed. A terminal launch can use
`chatgpt --ozone-platform=wayland` for the same explicit backend.

The earlier memory controls remain appropriate: Chromium keeps its bounded
memory and swap policy, and both ChatGPT scope families keep
`OOMPolicy=continue` so a child OOM does not unnecessarily terminate healthy
scope members. The latest event did not justify tightening those limits or
changing DNS; resolver queries succeeded despite concurrent DNSSEC warning
messages.
