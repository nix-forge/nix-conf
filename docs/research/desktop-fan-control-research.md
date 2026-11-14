# Quiet desktop fan control

Reviewed: 2026-11-05. Scope: MSI MAG B650 TOMAHAWK WIFI, Ryzen 7 7700X,
RTX 4070, ARCTIC Liquid Freezer II 280, ARCTIC top exhaust and three
Noctua NF-A12x25 PWM chromax.black.swap front intakes.

## Implemented policy

Use CoolerControl 5.0.1 and the dedicated `nct6687` driver. The original
`nct6683` driver exposes monitoring but read-only PWM attributes on this MSI
board; installing a GUI cannot add write support. Remove its explicit load and
`force=1` parameter and keep one driver owning the Super-I/O registers.
[Linux 7.2.9 driver](https://github.com/gregkh/linux/blob/v7.2.9/drivers/hwmon/nct6683.c),
[CoolerControl motherboard support](https://docs.coolercontrol.org/devices/motherboards).

The owner confirmed the wiring after initial RPM-based identification:

| Motherboard header | Driver channel | Connected group | Policy |
| --- | --- | --- | --- |
| PUMP_FAN1 | `fan2` | Liquid Freezer II pump/VRM assembly and daisy-chained radiator fans | CPU Tctl only; 60% minimum |
| SYS_FAN1 | `fan3` | ARCTIC top exhaust | Maximum CPU/GPU airflow demand; 35% minimum |
| SYS_FAN2 | `fan4` | Three front Noctuas | Maximum CPU/GPU airflow demand; 35% minimum |

The side radiator and front fans take air into the case; the top fan exhausts.
Do not infer wiring solely from labels or RPM: the top ARCTIC and radiator P14s
have overlapping speed ranges. Here, RPM and observation identified the Noctua
channel; physical connection information distinguished the top fan from the AIO.

**The AIO channel reports zero RPM despite the cooler operating.** Its PWM
command is readable and writable, but pump/radiator speed feedback is unavailable.
Zero must not be treated as a measured stall or a valid pump-speed estimate.
No stop/start calibration was performed on that circuit. The 60% floor is a
conservative operating choice, not a measured minimum or manufacturer requirement.
Restoring RPM feedback requires inspecting the physical tachometer connection
with the computer powered off; software cannot recover a missing tach signal.

The non-RGB Liquid Freezer II 280 has two P14 fans rated 200–1700 RPM and a
PWM-controlled 800–2000 RPM pump. Its shared cable controls the assembly together;
software cannot give the pump and radiator fans independent curves through that
single connection. The NF-A12x25 is rated to 2000 RPM and approximately 460 RPM
at 20% PWM. Published maxima are reference ranges, not exact installed speeds.
[ARCTIC specifications](https://www.arctic.de/media/92/24/d4/1690272957/Spec_Sheet_Liquid_Freezer_II_280_EN_update.pdf),
[ARCTIC revision-specific manuals](https://support.arctic.de/lf2-280),
[Noctua specifications](https://www.noctua.at/en/products/nf-a12x25-pwm-chromax-black-swap/specifications).

## Curves and noise response

The [first-start policy](../../hosts/nixos/desktop/local/hardware/fans.toml)
contains the exact graph points and device/sensor bindings. These use raw PWM
percentages; no calibration remapping is enabled.

- AIO: 60% through 60°C CPU Tctl, 70% at 70°C, 85% at 80°C, 100% at 90°C.
- Case CPU demand: 35% through 65°C, 45% at 75°C, 65% at 85°C, 100% at 92°C.
- Case GPU demand: 35% through 50°C, 45% at 60°C, 60% at 70°C, 80% at 78°C,
  100% at 83°C.

Use `k10temp` Tctl and the RTX 4070's GPU temperature. Combine the two case
**duty demands** with Max after applying their separate curves. CPU and GPU
normal temperature ranges differ, so averaging their raw temperatures would
produce a less suitable signal. The AIO remains independent of GPU monitoring.
[Mix profiles](https://docs.coolercontrol.org/cooling/mix-profiles).

A Standard function permits unrestricted upward duty changes, with 3°C and
15-second hysteresis applied only downward. Decreasing steps are limited to
three percentage points per update. Broad low-temperature plateaus avoid
chasing small CPU boost excursions; raw temperature remains the source for the
high-temperature ramp. No long temperature averaging window delays that ramp.
[CoolerControl functions](https://docs.coolercontrol.org/cooling/functions).

Limited-range measurements, sampled over eight-second steps, were:

| Group | Commanded duty | Final observed RPM |
| --- | ---: | ---: |
| Top ARCTIC | 45% | 913 |
| Top ARCTIC | 60% | 1081 |
| Top ARCTIC | 80% | 1362 |
| Top ARCTIC | 100% | 1556 |
| Front Noctua tachometer | 35% | 858 |
| Front Noctua tachometer | 50% | 1169 |
| Front Noctua tachometer | 75% | 1623 |
| Front Noctua tachometer | 100% | 2010 |

After applying the 35% case floors, live idle readings were approximately
720 RPM top exhaust and 850 RPM front intake. These support substantially
lower light-load speeds than the original approximately 1100/1360 RPM readings.
They do not establish a measured acoustic optimum: no microphone, sound-level
meter or controlled ambient comparison was used. A splitter's returned tachometer
also does not independently verify all three Noctuas. Preserve floor margin and
check physical operation after wiring changes.

## GPU fans

Keep the RTX 4070 fan channels firmware automatic while monitoring its temperature.
Read-only NVML queries reported two fan channels, both in automatic policy, at 0%
while the GPU was approximately 30–31°C. The advertised manual operating range
was 30–100%; automatic control retains the useful idle fan-stop behavior.

NVML offers fan setters without requiring an X11 control session, subject to
card/driver support. NVIDIA warns that its setter takes over thermal management.
No GPU fan setters were used here. There is no measured GPU acoustic problem
justifying replacement of its factory curve; increasing case airflow with GPU
heat is the chosen intervention.
[NVIDIA fan commands](https://docs.nvidia.com/deploy/nvml-api/latest/api/group__nvmlDeviceCommands.html),
[CoolerControl GPU support](https://docs.coolercontrol.org/devices/gpus).

## Persistence, recovery and validation

[The host module](../../hosts/nixos/desktop/local/hardware/fans.nix) selects
`kernelPackages.nct6687d`, whose module is named `nct6687`. Pinned source is
`4864fd681346119cf17417f82934a8ce05d88ff6`. B650 uses the default mapping; do not
force newer MSI alternate mappings. The driver supports firmware mode `2` and
attempts to restore changed channels on unload.
[Pinned source](https://github.com/Fred78290/nct6687d/tree/4864fd681346119cf17417f82934a8ce05d88ff6).

Mutable configuration, profile bindings and calibration live in
`/var/lib/coolercontrol`, using `CC_CONFIG_DIR` and systemd-managed state.
Systemd initializes the directory with mode 0700 and sets `UMask=0077`. After
startup, the observed directory mode is 0711; `config.toml` remains root-owned
with mode 0600. The source policy seeds a missing configuration once; later starts
preserve UI changes. Updating the seed does not overwrite an existing policy.
The API listens only on loopback. Upstream's notify, restart and 30-second
watchdog behavior remains selected.
[5.0.1 configuration](https://gitlab.com/coolercontrol/coolercontrol/-/blob/5.0.1/coolercontrold/daemon/resources/config-default.toml),
[packaged systemd unit](https://gitlab.com/coolercontrol/coolercontrol/-/blob/5.0.1/packaging/systemd/coolercontrold.service).

The booted-kernel driver and CoolerControl built in an isolated bounded private
store. The driver loaded successfully on 7.2.9-xanmod1, exposing writable controls.
The source policy passed CoolerControl's native `check` command. A settings-only
seed had initially caused a parser panic; the corrected structural tables and
Unmanaged profile were checked before live installation. Formatting and focused
publication scans passed.

Stopping CoolerControl returned all three owned headers to firmware mode `2`;
starting it reapplied the saved profiles. Process failure, suspend/resume and
an OS hang are distinct cases. A software watchdog does not guarantee cooling
during an OS hang, and CPU thermal protection does not replace a functioning pump.
Preserve working BIOS Smart Fan curves and correct PWM header modes.
[MSI manual](https://download-2.msi.com/archive/mnu_exe/mb/MAGB650TOMAHAWKWIFI.pdf).

The configured 7.2.11-xanmod1 desktop generation evaluated successfully in an
8 GiB bounded allocation. An earlier 4 GiB evaluation was OOM-killed; an ordinary
daemon-backed build had also been refused for insufficient host memory.
Those failed attempts are not passing results. The selected 7.2.11-xanmod1
driver and generated CoolerControl unit subsequently built successfully in an
8 GiB bounded private store; module vermagic matched that configured kernel.
An initial production validation attempt failed because root import had changed
the task's private store directory ownership. Restoring ownership only within
that private store resolved the failure; later root imports use read-only mode.

The bounded finite load check passed all payloads and drained its execution scope:
120 seconds CPU-only, 120 seconds discrete-GPU-only and 180 seconds combined.
CPU load phases reached 95.625°C and drove all three headers to 100%. The GPU
peaked at 64°C and approximately 211 W. The GPU phase immediately followed CPU
load, so its early CPU readings include cooldown from that phase. These short
checks establish ramp response, not prolonged radiator heat-soak equilibrium.

A controlled daemon SIGKILL was also recovered automatically: systemd incremented
its restart count, started a new process and reached readiness in 3.8 seconds.
Saved assignments were reloaded and both GPU fans remained in automatic policy.
This tests process recovery; it does not establish firmware takeover during
an OS hang. Suspend/resume remains untested.
A 7700X can target approximately 95°C during heavy multithreaded work; assess
controller response and the CPU's performance limits rather than treating that
reading alone as proof of cooling failure.
[AMD temperature and power explanation](https://community.amd.com/t5/gaming/ryzen-7000-series-processors-let-s-talk-about-power-temperature/ba-p/554629).

Following runtime validation, the full desktop build and activation passed on
2026-11-05 through the normal daemon-backed workload queue and the existing
operational deployment wrapper. Its deployment identity and additional host
settings were preserved. The activated generation is also the selected system
profile and default boot configuration.

CoolerControl now uses the enabled NixOS-owned unit under
`/etc/systemd/system/coolercontrold.service`; the temporary runtime unit and
its state drop-in were removed. The saved three header assignments, active PWM
control and both GPU automatic policies were verified after activation. The
local web interface returned HTTP 200 at `https://127.0.0.1:11987/`.

No reboot was performed. The running kernel remains 7.2.9-xanmod1 with its
already-loaded matching driver; the selected boot generation contains the
7.2.11-xanmod1 driver and declares `nct6687` for boot loading. Startup across an
actual reboot remains untested. The operating profile is an initial measured
tune, not exhaustive acoustic or thermal-equilibrium qualification.
