# Evening display light and sleep

Research date: 2026-09-06

The useful target is less melanopic light reaching the eyes before bed. Reducing short-wavelength output helps, but screen brightness, room lighting, exposure duration, and timing also matter. A warmer screen is a reasonable tool, with no guarantee that a particular color temperature will improve sleep. For this desktop, keep Noctalia and use 1900 K as a strong-filter starting point, with low hardware brightness and the full transition reached three hours before sleep. The sections below explain the evidence and settings. The implementation status at the end records the subsequently applied configuration.

## What the evidence supports

Short-wavelength light can suppress evening melatonin and delay the body clock. In a controlled human experiment, 6.5 hours of 460 nm light caused roughly twice the melatonin suppression and circadian delay of 555 nm light at equal photon density. This establishes wavelength sensitivity; it does not predict the size of an effect from ordinary desktop use. Green light still produced a response. [Lockley et al., 2003](https://pubmed.ncbi.nlm.nih.gov/12970330/)

The target extends into blue-cyan. The standard melanopic sensitivity curve peaks around 490 nm after accounting for the eye's filtering. Melanopic equivalent daylight illuminance, or melanopic EDI, weights the spectrum by this sensitivity and expresses the result as the amount of standard daylight that would provide the same melanopic stimulus. It differs from ordinary lux, which weights light for visual brightness. [Brown et al., figure 1](https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571), [CIE measurement definitions, table 2](https://files.cie.co.at/CIE_TN_015_2023.pdf)

Kelvin is an incomplete guide. In a study of 15 participants, two white light spectra had similar color temperatures and about 175 lux at the eye. The spectrum with more output between 450 and 500 nm suppressed melatonin by almost 50%; the other did not significantly suppress it relative to dim light. The researchers changed spectral power while maintaining the white appearance. This supports measuring emitted light rather than treating a warm appearance as proof. The study measured melatonin and alertness, not subsequent sleep improvement. [Souman et al., 2018](https://journals.sagepub.com/doi/10.1177/0748730418784041)

Brightness is consequential even at ordinary indoor levels. Phillips and colleagues studied 55 adults and found substantial differences in sensitivity. The estimated light level producing 50% melatonin suppression ranged from about 6 to 350 ordinary lux between individuals. These values describe their experimental spectrum and exposure protocol. They are not melanopic EDI thresholds or personal limits transferable to an arbitrary monitor. [Phillips et al., 2019](https://pmc.ncbi.nlm.nih.gov/articles/PMC6575863/)

## What screen experiments show

Schöllhorn and colleagues used a special five-primary display to change melanopic output while preserving luminance and color. Seventy-two healthy men aged 18 to 35 received 3.5 hours of evening exposure, starting four hours before habitual bedtime. Lower melanopic output produced higher evening melatonin concentrations and greater reported sleepiness across all four intensity groups. A significant reduction in time to fall asleep occurred in the brightest group; the three lower groups did not show significant sleep-latency differences. This is stronger evidence for changing actual spectral output than judging tint alone. It is a laboratory result with specialized hardware, a restricted sample, and only 18 people per intensity group. An ordinary RGB monitor cannot reproduce its independent spectral controls through software alone. [Schöllhorn et al., 2023](https://www.nature.com/articles/s42003-023-04598-4)

A practical phone trial gives a necessary limit on expectations. Duraccio and colleagues randomized 167 adults aged 18 to 24 to use an iPhone with Night Shift on, use it with Night Shift off, or avoid the phone during the hour before bed for seven nights. Wrist measurements showed no significant full-sample differences in sleep latency, duration, efficiency, or wake after sleep onset. A post-hoc subgroup favored no phone use on some outcomes, but that exploratory result should not carry the main conclusion. The trial does not show that spectrum is irrelevant; it shows that this consumer feature alone did not reliably improve the measured sleep outcomes in this sample. [Duraccio et al., 2021](https://www.sleephealthjournal.org/article/S2352-7218%2821%2900060-7/pdf)

Dim amber or red light generally offers a way to reduce melanopic exposure, but red light is not a sleep treatment. In a small nighttime experiment, both blue and red exposures changed EEG measures associated with alertness. Only the higher blue exposure reduced melatonin relative to the other conditions. Preserving melatonin and avoiding every alerting effect are different outcomes. [Figueiro et al., 2009](https://pubmed.ncbi.nlm.nih.gov/19712442/)

## Evidence-based exposure targets

The 2022 expert consensus recommends the following for healthy adults with regular daytime schedules, measured at the eye. These are general targets, not sharp boundaries between harmless and harmful exposure. [Brown et al., 2022](https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571)

| Period | Recommended melanopic EDI |
| --- | --- |
| Daytime | At least 250 lux, using daylight where available |
| Starting at least three hours before habitual bedtime | At most 10 lux |
| Sleeping | As dark as possible, at most 1 lux |

The CIE's 2024 position statement incorporates these recommendations and retains the CIE S 026 measurement system. It also identifies uncertainty about application to children, older adults, special health needs, and people working overnight. Evening visibility needs still matter. [CIE position statement, 2024](https://www.cie.co.at/publications/cie-position-statement-integrative-lighting-recommending-proper-light-proper-time-3rd)

## Practical inference for this desktop

Schedule strong spectral reduction relative to habitual bedtime, combine it with lower display luminance and dim room lighting, and turn the display off for sleep. The implementation should reduce emitted short-wavelength light. Its name, visual tint, or use of a shader versus a hardware color ramp cannot establish the physiological effect.

No trial above establishes a best monitor Kelvin setting. Actual melanopic reduction needs a spectrum measured at the normal eye position with representative screen content and room lighting. A brightness percentage, screenshot, or Kelvin setting cannot establish compliance with the exposure targets. The CIE method needs spectral irradiance or a valid spectrum-dependent conversion from ordinary illuminance. [CIE calculation method](https://files.cie.co.at/CIE_TN_015_2023.pdf)

## What your desktop currently does

Read-only inspection on 2026-09-06 found Noctalia enabled at 6500 K by day and
4200 K by night, with a custom 20:00 sunset and 06:30 sunrise. These values
came from `noctalia config export`, including the merged configuration.
`noctalia config validate` passed. The physical PG32UCWM on DP-4 was using
Hyprland's `srgb` preset at inspection time. Its configuration permits automatic
HDR for fullscreen HDR content.

The relevant repository files are
[`interactive-desktop.nix`](../homes/desktop/local/interactive-desktop.nix),
[`noctalia.nix`](../modules/home/desktop/noctalia.nix), and
[`hyprland.nix`](../homes/desktop/local/hyprland.nix).

Noctalia already sends separate red, green, and blue gamma tables through
Wayland. Hyprland applies them to the output gamma LUT. This reduces output
channel values without drawing a translucent colored window. The pinned
[Noctalia implementation](https://github.com/noctalia-dev/noctalia/blob/f96a407deb109c9db6f29db75e6fe487a5289e02/src/system/gamma_service.cpp)
and [Hyprland implementation](https://github.com/hyprwm/Hyprland/blob/ee0409623e2d6a683374b39a32e0ac3d087841aa/src/protocols/GammaControl.cpp)
confirm the mechanism. Hyprland can reject unsupported gamma tables, so source
inspection alone does not measure what the panel emits.

Calculated from Noctalia's pinned `kelvinToRgb` formula:

| Setting | Green table multiplier | Blue table multiplier |
| --- | ---: | ---: |
| 4200 K, current night setting | 0.826 | 0.686 |
| 2700 K | 0.654 | 0.343 |
| 2500 K | 0.624 | 0.275 |
| 2200 K | 0.574 | 0.154 |
| 1900 K | 0.517 | 0.000 |

Red remains 1.000 at these settings. These are digital table multipliers,
not percentages of emitted blue light or melatonin suppression. At 1900 K and
below, the implementation sets every blue-table entry to zero. This does not
establish zero short-wavelength emission or zero circadian stimulus. Display
primaries have spectra, and the remaining green output still matters.

## Settings I recommend for this desktop

Keep Noctalia as the single night-light controller. The existing module already
prevents enabling its night light alongside the separate Hyprsunset service.
Changing to another application would not by itself improve sleep protection.

For your preference to remove the blue output channel, I would start at
**1900 K**, alongside low hardware brightness. This choice comes from the
implementation above, not a clinical trial establishing an optimal temperature.
Expect strong amber coloration and loss of visibility for saturated blue
content. If that interferes with work, 2500 to 2700 K is a practical compromise
that retains some blue channel output. Keep daytime at 6500 K.

Aim to reach the full night setting three hours before intended sleep.
Noctalia's one-hour fade is centered on the configured time, so set `sunset`
to bedtime minus three hours and thirty minutes. The present 20:00 setting
finishes its fade at 20:30. That is three hours before a 23:30 bedtime.
[Noctalia scheduling documentation](https://docs.noctalia.dev/noctalia/services/night-light/)

For example, if sleep is at 23:00 and waking is at 07:00, this is a proposed
host-local Nix setting:

```nix
desktop.noctalia.nightLight = {
  enable = true;
  dayTemperature = 6500;
  nightTemperature = 1900;
  sunset = "19:30"; # Fades 19:00 to 20:00.
  sunrise = "06:30"; # Fades 06:00 to 07:00.
};
```

The wake-time example assumes the display is off while you sleep. Keep the
screen off throughout sleep even if its morning transition has started.
Bedtime and waking time were not supplied when this example was drafted.

Use Noctalia's existing DDC/CI brightness control to find the lowest comfortable
hardware brightness. No universal percentage maps to the research's exposure
limits. Dim room lights too, favoring dim amber or warm lighting over bright
cool-white lighting. Color temperature alone cannot establish compliance.

Prefer SDR during the pre-bed period. The ASUS manual disables its hardware
Blue Light Filter and Color Temp controls in HDR, and ordinary brightness
adjustment is restricted to Adjustable HDR. Its Blue Light Filter level 4 also
locks brightness, while levels 1 through 3 allow adjustment. Those restrictions
make the existing software filter plus controllable SDR brightness the better
starting point here. These monitor features are not evidence of a sleep
benefit. [ASUS PG32UCWM manual, sections 3.1.2.2 and 3.4](https://dlcdnets.asus.com/pub/ASUS/LCD%20Monitors/PG32UCWM/ASUS_PG32UCWM_EN.pdf)

## What would verify the result

A display spectroradiometer measuring spectral irradiance at your normal eye
position can quantify combined screen and room exposure as melanopic EDI.
A monitor brightness percentage, ordinary lux reading, or screenshot cannot
establish that value. The recommendations here remain practical starting
settings until that measurement exists.

For a basic functional check after applying a setting, compare a fixed white
and blue test image with night light off and forced on. The screen should lose
blue intensity without lifting black areas. Check again after monitor sleep
and any HDR transition. This checks whether the filter appears to work, not
whether a physiological exposure target has been achieved.

## Implementation status

At the user's request on 2026-09-06, the host-local configuration now sets
1900 K at night, 6500 K by day, sunset at 19:30, and sunrise at 06:30. This uses
the example 23:00 bedtime, since a personal bedtime was not supplied. The evening
fade runs from 19:00 to 20:00; the morning fade runs from 06:00 to 07:00.

The generated Noctalia configuration built successfully on `desktop`. The two
changed night-light values were applied to the live configuration, preserving
the existing unrelated icon hook. Noctalia accepted `config-reload`, its merged
configuration passed validation, and an export confirmed the new values.
The Nix source preserves these settings for subsequent system rebuilds.

Hardware brightness remains manually adjustable through Noctalia. HDR policy
was not changed; prefer SDR content before bed as recommended above. No spectral
measurements or sleep-outcome tests were performed.
