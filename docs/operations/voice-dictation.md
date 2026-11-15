# Free offline voice dictation

The desktop selects Voxtype with its ONNX backend; macOS selects Handy. Both use
Parakeet V2 int8 for English and unload the speech model after transcription.
No API key, subscription, cloud transcription, or separate cleanup model is used.
Audio and inference still need memory while recording and transcribing; unloading
adds a loading delay to each recording.

## Use

One service per machine handles Zen, T3 Code, and other applications. There is
no browser extension, Zen-specific recording command, or second Whisper model
to configure. Use the system-wide shortcut rather than a browser or T3 microphone
button, which may invoke another transcription path.

Focus the T3 Code composer or another text field, then toggle recording:

| Platform | Start / finish | Cancel |
| --- | --- | --- |
| Hyprland | Ctrl+Alt+D | Ctrl+Alt+Shift+D |
| macOS | Ctrl+Option+D | Ctrl+Option+Shift+D |

For a Zen search, press **Ctrl+L** on Linux or **Command+L** on macOS first, then
start dictation. The same shortcut works in web forms and T3's composer. Finish
dictation, review the text, then press Enter when ready. Starting dictation does
not change application focus.

Finished text is pasted for review. Dictation does not press Send. On Linux,
recording and transcription notifications provide feedback without an OSD helper.
On Linux, a paste failure leaves the transcript in the clipboard for manual recovery.

On macOS, open **Handy** from the managed Applications directory. Complete its
permission prompts and enable Handy under **System Settings → Privacy & Security
→ Microphone** and **Accessibility**. These grants belong to macOS and require
the user's approval. The selected model is already installed. Keep the microphone
set to the intended device; choose a wired or built-in mic if Bluetooth headset
capture is unclear. Handy's custom vocabulary remains editable in its UI.

The configuration is in [the dictation module](../../modules/home/desktop/dictation.nix).
The Linux compositor handles shortcuts without access to all input devices. The
native user service starts the app at login. It also installs the same shortcuts
when the Linux service starts. On macOS, the app owns its shortcuts and launchd
owns its lifetime; in-app autostart is off to avoid duplicate ownership.
The old native Fn/Globe dictation assignment is reset; macOS may need a restart
before that key stops opening native Dictation.

## Health and validation

On Linux, inspect `systemctl --user status voxtype` and restart it with
`systemctl --user restart voxtype`. On macOS, inspect
`launchctl print gui/$(id -u)/com.pais.handy.service`. Open the Handy app to inspect
microphone selection and permission status.

Validation on 2026-11-08 included configuration reconciliation tests, isolated
Home Manager builds, and native transcription of the public whisper.cpp JFK
sample. This checks a working recognizer, not accuracy on technical prompts or a
live end-to-end paste into T3. The temporary macOS signing repair seals Handy's
source-built bundle after packaging; it is ad-hoc signed, not vendor notarized.
Apple's strict deep signature verification passes for the installed bundle.

The consolidated feature is evaluated in both complete host configurations as
well as an isolated Home Manager profile. Preferences-preservation tests run on
the native Mac. Changes to shortcuts do not require another model download.

Sources: [Voxtype](https://github.com/peteonrails/voxtype),
[Handy](https://github.com/cjpais/Handy),
[Parakeet catalog and pinned checksum](https://github.com/cjpais/Handy/blob/v0.9.6/src-tauri/src/managers/model.rs).
