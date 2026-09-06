# Linux audio cutouts under CPU load

Research date: 2026-09-05

Scope: NixOS desktop with PipeWire 1.6.8, WirePlumber 0.5.15, BlueZ 5.87,
AirPods Pro 2 on A2DP AAC, and the device rules in
`hosts/nixos/desktop/local/audio.nix`.

## Conclusion

The live evidence points to two faults that reinforce each other:

1. The desktop forces nearly every audio path to use unusually small buffers.
   The graph runs at 128 frames and 48 kHz, which gives PipeWire 2.67 ms to
   complete each cycle. The Pulse compatibility server targets only 256 frames
   of playback buffering, or 5.33 ms. The USB batch device has an explicitly
   limited effective hardware buffer of 192 frames, or 4 ms.
2. The audio processes started at boot without realtime scheduling. Before the
   services were restarted, every `data-loop.0` thread used ordinary
   `SCHED_OTHER` scheduling and the main processes ran at nice level 0. A
   restart after RTKit was active changed the data loops to `SCHED_RR` priority
   20 and the main processes to nice level -11.

This is enough to explain cutouts under light CPU load. Before the restart,
`pw-top` showed four errors on the AirPods driver and 72 to 73 errors on active
application streams. The PipeWire journal logged roughly 292 to 296
`spa.audioconvert: out of buffers` events every two seconds. PipeWire defines
the `ERR` column as xruns and errors. Driver xruns mean that the graph missed a
cycle deadline, often because scheduling was delayed. [The `pw-top` manual
defines these counters and the relationship between quantum, rate, and the
deadline](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-top_1.html).

The AirPods remained on A2DP AAC. The CPU was already using the performance
governor and performance EPP, Wi-Fi was on 5.805 GHz, and the kernel journal had
no Bluetooth, MediaTek firmware, USB, or xHCI transport error after startup.
Those observations make CPU frequency policy and 2.4 GHz Wi-Fi coexistence poor
first explanations for this incident.

## Live evidence

| Check | Before audio-service restart | After restart | Meaning |
| --- | --- | --- | --- |
| PipeWire graph | 48 kHz, quantum 128 | unchanged | 2.67 ms graph deadline, 375 cycles per second |
| PipeWire data loop | `TS`, no RT priority | `RR`, priority 20 | RTKit was available but did not promote the boot-started process |
| PipeWire main process | nice 0 | nice -11 | the restart also restored PipeWire's requested main-thread priority |
| `pw-top` | AirPods `ERR=4`; Spotify `ERR=72`; game `ERR=73` | counters reset with new process | actual missed deadlines, not a subjective codec complaint |
| PipeWire journal | hundreds of `out of buffers` messages per interval | no new warnings immediately after restart | buffer starvation tracked the bad scheduler state |
| AirPods | A2DP, codec `aac`; transport format 44.1 kHz in the sampled session | A2DP AAC | high-quality Bluetooth profile stayed selected |
| RTKit | active, max RT priority 20, canary thread `RR/99` | same | daemon and privileges were healthy |
| CPU | `amd-pstate-epp`, performance governor, performance EPP | same | no reason to force another CPU policy |
| Wi-Fi | channel 161, 5.805 GHz | same | not sharing the 2.4 GHz band with Bluetooth |

The restart result does not prove why the first RTKit requests were ineffective.
It does prove that the same binaries and policy can obtain the intended
priority once RTKit is already running. The evaluated NixOS configuration has
`security.rtkit.enable = true`, but `rtkit-daemon.service` has no `wantedBy`
target and was merely linked. The boot journal puts RTKit and PipeWire startup
in the same one-second interval. That is consistent with a startup-order race,
but the timestamps are not precise enough to identify the exact interleaving.
This PipeWire build explicitly sets `rtportal.enabled = false`, so the audio
daemon talks directly to RTKit. PipeWire 1.6.8 uses blocking calls to read the
RTKit limits, but sends the final priority request asynchronously without
waiting for the method reply. [The 1.6.8 module source contains the direct
RTKit path and asynchronous priority calls](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/1.6.8/src/modules/module-rt.c).

## Why the current buffering is fragile

PipeWire's 1.6.8 default graph quantum is 1024 frames. A follower can suggest a
smaller quantum, and the driver uses the smallest active suggestion. The
desktop instead sets the default and minimum to 128 and adds `node.latency =
128/48000` to native and Pulse streams. That makes the low value pervasive.
[PipeWire documents `node.latency` as a graph latency suggestion and explains
how follower suggestions select the driver's quantum](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-top_1.html).

The Pulse settings are more aggressive still:

| Setting | Desktop | PipeWire 1.6.8 default |
| --- | --- | --- |
| `pulse.min.req` | 128 frames, 2.67 ms | 256 frames, 5.33 ms |
| `pulse.default.req` | 128 frames, 2.67 ms | 960 frames, 20 ms |
| `pulse.default.tlength` | 256 frames, 5.33 ms | 96000 frames, 2 seconds |
| `pulse.min.quantum` | 128 frames, 2.67 ms | 256 frames, 5.33 ms |

The two-second upstream target only applies when a Pulse client does not ask
for another value. It is not a requirement to impose two seconds of desktop
latency. The important point is that PipeWire explicitly says lower `req`,
`tlength`, `frag`, and minimum quantum values trade CPU overhead and underrun
margin for lower latency. [The protocol documentation defines every value and
the tradeoff](https://pipewire.pages.freedesktop.org/pipewire/page_module_protocol_pulse.html).

The USB tuning is also too tight. WirePlumber says most USB audio devices are
ALSA batch devices. For a batch device, the effective buffer size is
`period-num * period-size / 2`. The current values therefore create a
`3 * 128 / 2 = 192` frame hardware buffer. WirePlumber already detects batch
devices and adjusts timing when these properties are left unset. [Its ALSA
documentation gives the batch-device formula and automatic behavior](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html#alsa-buffer-properties).

These buffer sizes do not improve fidelity. They only reduce latency. A larger
quantum still carries the same samples and AAC bitstream; it gives the CPU more
time to meet each deadline.

## Recommendations ranked by evidence

### 1. Remove the global 128-frame client and Pulse overrides

Confidence: high. Risk: low. Expected effect: large reduction in xruns and
`out of buffers` failures.

Keep the graph at 48 kHz, but start with a 512-frame default quantum, a
256-frame minimum, and a 2048-frame maximum. This gives the ordinary graph a
10.67 ms period while retaining a controlled 5.33 ms lower bound for a client
that has a real latency requirement. It also restores the ability to move to a
larger safe quantum. Remove the broad native-client and Pulse
`stream.properties.node.latency` rules. Return the Pulse buffer properties to
their upstream defaults for the first verification run.

The exact 512-frame choice is a workstation recommendation derived from the
observed failures, not an upstream mandate. It has four times the scheduling
margin and one quarter of the wake-up rate of 128 frames. If the load test
still increments `ERR`, raise the minimum to 512 or the default to 1024. The
upstream default is 1024 frames, or 21.33 ms at 48 kHz. [PipeWire documents the
clock defaults and warns that rate changes interact with kernel and Bluetooth
behavior](https://pipewire.pages.freedesktop.org/pipewire/page_man_pipewire_conf_5.html).

### 2. Start RTKit before logins can start PipeWire

Confidence: high that RT priority was absent, medium that D-Bus activation
ordering is the whole cause. Risk: low.

Keep `security.rtkit.enable = true`. Add RTKit to `multi-user.target` and order
it before `systemd-user-sessions.service`. Then the direct RTKit broker is
already accepting calls before the Hyprland user session can launch PipeWire.
Preserve PipeWire's existing direct-RTKit behavior. Verify the result after a
cold boot, not only after restarting audio services.

Do not replace RTKit with broad `@audio` PAM limits. PipeWire uses RTKit when a
regular user lacks direct `RLIMIT_RTPRIO`. RTKit limits users, processes,
threads, and request rate; requires `SCHED_RESET_ON_FORK`; checks PolicyKit;
and has a watchdog that demotes realtime threads if the machine becomes
unresponsive. [PipeWire documents its RTKit fallback](https://pipewire.pages.freedesktop.org/pipewire/page_module_rt.html),
and [RTKit documents its security controls](https://github.com/heftig/rtkit/blob/master/README).
The pinned [NixOS RTKit module also confines the daemon with a read-only
system, private devices, namespace restrictions, syscall filtering, and no
network access](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/security/rtkit.nix).

Do not disable the RTKit canary as a first fix. Its purpose is to recover from
a runaway realtime process. RTKit has a documented suspend bug that can
incorrectly demote threads after `s2idle`, but this boot had no suspend or
resume before the failure. [The upstream issue describes that specific
failure](https://github.com/heftig/rtkit/issues/13). If a later test reproduces
cutouts only after resume, restart the audio services on resume or fix the
upstream RTKit behavior. Removing the watchdog weakens the machine's recovery
boundary.

### 3. Let PipeWire size the USB batch-device buffer

Confidence: high that the current buffer is too small, although it does not
affect AirPods playback. Risk: low.

Keep the device-scoped `audio.rate = 48000` rule. Remove the explicit
`api.alsa.period-size`, `api.alsa.period-num`, and `api.alsa.headroom` values.
PipeWire 1.6.8 derives a batch device's period from the graph quantum and can
use the hardware's available buffer instead of forcing three tiny periods.
[The 1.6.8 ALSA implementation contains the automatic sizing
path](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/1.6.8/spa/plugins/alsa/alsa-pcm.c).

If the USB interface alone still xruns after automatic sizing, measure its
negotiated period and buffer first. Add headroom or explicit periods only for
the failing UCM node and only after the test shows a repeatable benefit.

### 4. Keep the existing quality choices

Confidence: high. Risk: low.

Keep a stable 48 kHz graph. The sampled AirPods session negotiated 44.1 kHz,
so PipeWire resampled between the graph and the device. This is normal. The
default resampler quality is 4, and PipeWire describes its exponential filter
as a quality and performance compromise with about 150 dB stopband
attenuation. Higher values consume more CPU and add filter latency. Raising
the resampler to 10 or 14 while diagnosing missed deadlines would work against
the reliability goal. [PipeWire documents the quality range and CPU
tradeoff](https://pipewire.pages.freedesktop.org/pipewire/page_man_pipewire-props_7.html#resampler-options).

Keep the AirPods on `a2dp-sink` with codec `aac`, AAC VBR mode 5, and automatic
headset-profile switching disabled. Do not use HFP during ordinary listening.
PipeWire 1.6.8 defaults its FDK-AAC encoder to VBR mode 5 when no override is
present, so the explicit setting states the intended maximum quality rather
than adding work beyond the upstream default. [The exact 1.6.8 AAC default is
in the codec source](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/1.6.8/spa/plugins/bluez5/a2dp-codec-aac.c).

Do not enable arbitrary high sample rates or disable resampling. PipeWire notes
that rate switching is disabled by default because of kernel and Bluetooth
issues, and a device that cannot match the graph rate needs the resampler to
connect. A 96 or 192 kHz graph cannot improve an AAC Bluetooth link.

### 5. Treat radio or codec faults as a second-stage test

Confidence: low for the current incident. Risk of diagnostic test: low.

If audio still cuts out while `pw-top` shows no new errors and every data loop
remains `RR/20`, then inspect the Bluetooth transport. BlueZ describes A2DP as
AVDTP media over L2CAP and provides `btmon` decoding for the signaling and
media channels. [The BlueZ A2DP trace guide shows the expected channel
sequence](https://github.com/bluez/bluez/blob/master/doc/btmon-a2dp.rst).

Capture one failure with `btmon` and compare AAC with SBC only as a temporary
diagnostic. If both fail at the same moment, suspect the radio, firmware, or
controller path. If AAC alone fails with clean PipeWire counters, investigate
the encoder and transport MTU. Restore AAC afterward. The current 5 GHz Wi-Fi
association already avoids ordinary 2.4 GHz Wi-Fi contention, and no kernel
log points to a controller reset.

### 6. Do not change the CPU governor or pin audio threads yet

Confidence: high. Risk avoided: power, heat, and new scheduler interactions.

The host already runs `amd_pstate=active`, the performance governor, and
performance EPP. In active mode, firmware selects performance within the OS
energy-performance hint. [The kernel AMD P-state documentation defines this
control path](https://docs.kernel.org/admin-guide/pm/amd-pstate.html#active-mode).
There is no evidence that another governor can fix this failure.

Likewise, do not disable `irqbalance`, isolate CPUs, add `thread.affinity`, or
increase realtime priorities above RTKit's limit before measuring a remaining
problem. Realtime scheduling plus sane buffers should be enough for this Zen 4
desktop.

## Secure configuration shape

The intended Nix configuration is small:

```nix
services.pipewire.extraConfig.pipewire."90-desktop-audio"."context.properties" = {
  "default.clock.rate" = 48000;
  "default.clock.allowed-rates" = [ 48000 ];
  "default.clock.quantum" = 512;
  "default.clock.min-quantum" = 256;
  "default.clock.max-quantum" = 2048;
};

# Do not add global node.latency rules to client.conf or pipewire-pulse.conf.
# Let PipeWire choose period and buffer values for the USB batch device.

systemd.services.rtkit-daemon = {
  wantedBy = [ "multi-user.target" ];
  before = [ "systemd-user-sessions.service" ];
};
```

Preserve the per-user PipeWire mode. The evaluated desktop has
`services.pipewire.systemWide = false`, so the NixOS module runs PipeWire,
pipewire-pulse, and WirePlumber as user units instead of opening one service to
members of a system-wide `pipewire` group. The NixOS module says system-wide
mode is not recommended. [The pinned module defines that boundary and its
default](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/services/desktops/pipewire/pipewire.nix#L162-L175).

Keep the Pulse and native PipeWire listeners on their Unix sockets in the
user's runtime directory. Do not add TCP addresses or open RAOP ports for this
repair. Those changes do not improve local playback and create network-facing
audio services. Keep the existing bounded Bluetooth pairing window and secure
connection policy. They are unrelated to the xrun problem and should not be
relaxed.

PipeWire already has `mem.allow-mlock = true`. The live process limit was 8 MiB
and the process had no swap use. `mem.warn-mlock` is false by default, so the
absence of a warning does not prove that every lock succeeded. Do not grant
unlimited memlock to an entire login group without evidence. PipeWire says
locking audio memory avoids page-fault hiccups, but it also exposes a warning
mode for checking failures.
[The configuration reference documents `mem.allow-mlock`, `mem.warn-mlock`,
and the resource limits](https://pipewire.pages.freedesktop.org/pipewire/page_man_pipewire_conf_5.html).
If a later trace shows `ENOMEM` from `mlock`, raise the limit only for the audio
services or enable the warning temporarily to size the requirement.

## Verification

Run these checks as the logged-in desktop user after deployment and again after
a cold boot.

Confirm the graph and codec:

```bash
pw-metadata -n settings 0
wpctl status -n
wpctl inspect AIRPODS_NODE_ID
```

Expected results are a 48 kHz graph, a 512-frame default quantum, no forced
quantum, and `api.bluez5.profile = "a2dp-sink"` with
`api.bluez5.codec = "aac"`.

Confirm scheduling. The main threads should have nice level -11, and each
`data-loop.0` should show class `RR` with priority 20:

```bash
for pid in $(pgrep -x pipewire) $(pgrep -x pipewire-pulse) $(pgrep -x wireplumber); do
  ps -T -p "$pid" -o pid,tid,cls,rtprio,pri,ni,psr,pcpu,comm
done
```

Confirm deadline stability while audio is playing:

```bash
pw-top -b -n 45
journalctl --user -b \
  -u pipewire.service \
  -u pipewire-pulse.service \
  -u wireplumber.service \
  --no-pager | grep -E 'out of buffers|xrun|underrun|error|failed'
```

`ERR` must remain unchanged. There should be no recurring `out of buffers`
message. Repeat while running the same light workload that previously caused a
dropout. Then run a bounded CPU test if `stress-ng` is available:

```bash
stress-ng --cpu 1 --timeout 30s --metrics-brief
```

Test both the AirPods and the USB output. If only USB fails, inspect the actual
ALSA buffer properties with `wpctl inspect USB_NODE_ID` and the kernel USB
log. If only AirPods fails with clean PipeWire error counters, record a short
Bluetooth trace:

```bash
sudo btmon --write /tmp/airpods-cutout.btsnoop
```

Stop the trace after one reproduced event. It contains Bluetooth addresses and
protocol metadata, so keep it local and delete it after inspection.

Finally, check boot ordering and the RTKit safety boundary:

```bash
systemctl is-active rtkit-daemon.service
systemctl show rtkit-daemon.service -p ActiveEnterTimestamp -p UnitFileState
cat /proc/sys/kernel/sched_rt_period_us
cat /proc/sys/kernel/sched_rt_runtime_us
```

The Linux scheduler reserves and limits realtime CPU bandwidth through these
two sysctls. Bad values can make the system unstable, so this repair should not
change them. [The kernel scheduler documentation explains the defaults and
safety warning](https://docs.kernel.org/scheduler/sched-rt-group.html#default-behaviour).

## Applied result

The configuration was deployed on 2026-09-05. The live graph reported 48 kHz,
a 512-frame quantum, a 256-frame minimum, a 2048-frame maximum, and no forced
quantum. PipeWire, PipeWire Pulse, and WirePlumber each obtained `SCHED_RR`
priority 20 for their data loop and nice level -11 for the main process.

A silent 48 kHz USB playback stream was then tested for 15 seconds with 15
normal-priority CPU workers on the 16-thread desktop. The sink and client both
remained at a 512-frame quantum, and neither error counter increased. With the
manual ALSA period settings removed, WirePlumber selected a 256-frame period,
128 periods, and 256 frames of headroom for that USB node. No `out of buffers`,
xrun, underrun, failure, or error message appeared in the user audio journal.

The AirPods were unavailable after the service restart, so their transport
could not be repeated after deployment. Pairing, bonding, trust, the persistent
default sink, AAC VBR mode 5, and the A2DP profile policy remained configured.
Before deployment, the same 512-frame runtime quantum produced zero AirPods
sink or client errors under the 15-worker test; the 128-frame configuration had
produced 227 client errors in the corresponding test.
