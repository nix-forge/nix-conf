# Webcam privacy without interrupting calls

Reviewed: 2026-09-09. Scope: Brio 101 on NixOS with Hyprland, PipeWire,
native Zoom, and Noctalia revision
`4ea0a7f0c7d00ac559a1029ccf8d0d1270b23c08`.

## Answer

Keep the known webcam authorized in USBGuard and close its physical shutter
between calls. Retain browser permission prompts and the existing desktop
capture indicators. Configure Zoom to join with video off and microphone muted
through its supported settings UI. This is a proportionate setup for ordinary
calls where the objective is modest extra protection and easy access.

Blocking the complete USB device until an administrator enables it gives
stronger isolation, but adds a privileged operation and device reconnection
before each call. It is a poor default for this requirement. The recommended
controls address unwanted images, accidental meeting transmission, and visible
capture activity. They do not prevent every native application from opening an
authorized camera or microphone.

## Findings and sources

| Control | Protection and limit |
| --- | --- |
| Brio 101 shutter | Logitech specifies an integrated privacy shutter, separate mono microphone, and 1080p at 30 fps. Covering the lens prevents useful room images. Treat the shutter as an optical cover; Logitech's specifications do not establish an electrical microphone disconnect. [Brio 101 specifications][brio] |
| Narrow USBGuard allow rule | USBGuard authorizes devices using attributes such as device ID, hash, and interface set. Keep a specific allow rule and the policy for other devices. This is USB device authorization, not application consent. [Rule language][usbguard] |
| Zoom join settings | Zoom supports joining with the microphone muted and video off. These reduce accidental transmission within Zoom; they are application behavior rather than an OS access boundary. [Zoom mute-on-join guide][zoom-mute], [client settings][zoom-settings] |
| Browser prompts | Firefox asks websites for camera and microphone permission and can remember or revoke each decision. Keep prompts and grant access only to intended sites. These permissions govern websites inside Firefox. [Mozilla permission guide][firefox] |
| Noctalia privacy indicator | The pinned implementation derives capture activity from PipeWire links and displays application names on hover. Keep it as useful feedback. It neither grants permission nor observes every capture route. [Pinned widget documentation][privacy-doc], [PipeWire implementation][privacy-source] |

Noctalia's `PipeWireService::rebuildState` builds its capture list from
`m_links`. A program opening a V4L2 device directly need not create a PipeWire
video link. The resulting inference is that native camera capture can occur
without a Noctalia camera indicator. An idle indicator is not proof that the
camera is inaccessible. Microphone streams that traverse PipeWire can still
appear independently. [Pinned implementation][privacy-source]

The Camera portal offers `AccessCamera` and a permission-controlled
`OpenPipeWireRemote`. Its access module manages portal-created clients and
ignores connections from other process IDs. Enabling the portal therefore
does not add a universal camera permission prompt to unsandboxed native
applications with direct device access. Screen-sharing portal support is a
separate capability. [Camera API][camera-portal], [PipeWire portal integration][portal-pipewire]

Switching Zoom to Flatpak solely for camera consent is not justified. The
Flathub manifest retrieved on the review date grants `--device=all`,
`--socket=pulseaudio`, and X11 access. Flatpak documents that the PulseAudio
permission includes microphone access and that device grants are static.
The package has other sandbox benefits, but these grants do not provide
per-call camera and microphone prompts. Tightening them requires separate
compatibility testing. [Zoom manifest][zoom-flatpak], [Flatpak permissions][flatpak]

AppArmor can constrain applications covered by enforced profiles. Its own
architecture documentation states that applications without corresponding
loaded policy remain unconfined. A Zoom profile would limit Zoom; it would
not create a system-wide webcam allowlist for every other application.
Adding comprehensive application confinement is a separate project.
[AppArmor architecture][apparmor]

## Validation and limits

This investigation read the repository's existing Noctalia and Zoom research,
the locally available pinned Noctalia source, and the primary sources above.
The source confirms the indicator's PipeWire-link dependency. It does not
establish which capture route a particular Zoom session uses.

No new camera capture, audio recording, shutter test, Zoom meeting, Flatpak
trial, or AppArmor enforcement test ran for this note. The accompanying
[Zoom investigation](zoom-research.md) records its own local capture and
integration results. Its successful local capture does not establish received
meeting resolution or official vendor support for NixOS. Logitech's published
Brio 101 compatibility list names Windows, macOS, and ChromeOS, but not Linux.
[Brio 101 specifications][brio]

## Implication for this repository

Remove the mandatory default-off webcam policy and per-call privileged
launchers. Restore the narrow trusted-device allow rule. Preserve existing
camera format negotiation, automatic image controls, native Zoom integration,
and desktop capture indicators. This approach introduces no additional video
conversion or monitoring service. Apply and verify runtime changes separately;
this research note changes no running policy.

[brio]: https://support.logi.com/hc/en-ca/articles/16131499767191-Specification-Brio-101
[usbguard]: https://usbguard.github.io/documentation/rule-language
[zoom-mute]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062614
[zoom-settings]: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060612
[firefox]: https://support.mozilla.org/en-US/kb/how-manage-your-camera-and-microphone-permissions
[privacy-doc]: https://github.com/noctalia-dev/noctalia/blob/4ea0a7f0c7d00ac559a1029ccf8d0d1270b23c08/docs/user/bar/widgets/privacy.mdx
[privacy-source]: https://github.com/noctalia-dev/noctalia/blob/4ea0a7f0c7d00ac559a1029ccf8d0d1270b23c08/src/pipewire/pipewire_service.cpp
[camera-portal]: https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Camera.html
[portal-pipewire]: https://flatpak.github.io/xdg-desktop-portal/docs/pipewire.html
[zoom-flatpak]: https://github.com/flathub/us.zoom.Zoom/blob/master/us.zoom.Zoom.json
[flatpak]: https://docs.flatpak.org/en/latest/sandbox-permissions.html
[apparmor]: https://apparmor-documentation-c38b15.gitlab.io/documentation/in-depth/architecture/overview/
