# Minecraft launchers for Linux

Research date: 2026-09-06

## Recommendation

Choose Prism Launcher for Minecraft Java Edition on Linux. It combines separate game instances with built-in Modrinth and CurseForge mod management, broad modpack support, and a Qt desktop interface. These are documented capabilities, not a claim that its Minecraft frame rate beats other launchers. [Prism overview](https://prismlauncher.org/)

Prism is also the best fit for this repository. `homes/desktop/default.nix` already imports the `prismlauncher` module, and `modules/home/prismlauncher.nix` installs `pkgs.prismlauncher`. Prism documents nixpkgs and its own flake as Linux installation options. Its Java guide says the NixOS package bundles Java. [Linux downloads](https://prismlauncher.org/download/linux/) and [Java installation](https://prismlauncher.org/wiki/getting-started/installing-java/)

This comparison concerns Java Edition. Microsoft's platform list supports Java Edition on Linux; its PC Bedrock Edition runs on Windows. A Bedrock requirement needs a separate assessment. [Minecraft PC product page](https://www.xbox.com/en-us/games/store/minecraft-java--bedrock-edition-for-pc/9NXP44L49SHJ)

## Comparison

The verdicts below are judgments based on the linked product documentation. No launcher was installed or benchmarked for this research.

| Launcher | Main strengths | Why choose it |
| --- | --- | --- |
| Prism Launcher | Separate instances and accounts; installs and updates individual mods from Modrinth and CurseForge; Qt interface; GPL-3 licensing. [Overview](https://prismlauncher.org/) | Best general choice, especially for a Linux user who wants both vanilla and modded instances. |
| ATLauncher | Packs from ATLauncher, CurseForge, Modrinth and Technique; automatic Java selection; save backups; creation and execution of servers for ATLauncher packs. [About](https://atlauncher.com/about) | Strong alternative if its pack workflow or server management suits you. |
| Modrinth App | Integrated Modrinth browsing, mod updates, profile import and sharing. Its download page labels it Beta and explicitly warns of Linux issues, recommending Prism if the app is unstable. [App page](https://modrinth.com/app) | Worth trying if you prefer its interface and mainly use Modrinth content. The project's own Linux warning keeps it below Prism as a default recommendation. |
| Official Minecraft Launcher | Mojang's distribution and Java Edition installation management; Linux support appears in its launcher installation guidance. [Installation guide](https://help.minecraft.net/hc/en-us/articles/23907917790093) and [installation management](https://help.minecraft.net/hc/en-us/articles/23431114561037-Troubleshooting-Launching-Minecraft-from-the-Minecraft-Launcher) | Reasonable for someone who wants the official route for vanilla Minecraft. Prism's documented mod management makes it more useful for the broader request here. |
| MultiMC | Separate instances, per-instance Java settings, mod loaders, logs, world management and modpack imports. Linux binaries require Qt5. Branding and authentication API keys have redistribution restrictions. [Official site](https://multimc.org/index.html) | Still a credible option, particularly for existing users. Prism's direct mod downloading and explicit redistributability make it the better starting point for this NixOS configuration. |

ATLauncher publishes Linux `.deb` and `.rpm` downloads and links to AUR and Flathub packages. Its current download page includes fixes for Minecraft 26.1, NeoForge downloads and CurseForge file downloads. These provide concrete evidence of compatibility work, although this review does not compare release cadence numerically. [Downloads and changelog](https://atlauncher.com/downloads)

Modrinth's current Linux download page points first to Flathub. Its help center describes third-party packages, including Flatpak, as community maintained rather than maintained by Modrinth staff. [App downloads](https://modrinth.com/app) and [third-party package guidance](https://support.modrinth.com/en/articles/9298760-third-party-packages)

## Prism details that affect the decision

Prism's documented modpack sources include ATLauncher, CurseForge, Modrinth, Technique, FTB Legacy and FTB App Import. FTB App Import requires an existing pack installation in the FTB App; it should not be described as unrestricted direct installation of all current FTB packs. Local `.zip` and `.mrpack` imports are also supported. [Modpack guide](https://prismlauncher.org/wiki/getting-started/download-modpacks/)

Some CurseForge packs require downloading individual components through a browser. Prism's CurseForge integration does not remove those distribution restrictions. [CurseForge guidance](https://prismlauncher.org/wiki/help-pages/flame-platform/)

Maintenance is current. Prism 11.1.0 was released on September 3, 2026, with fixes including excessive configuration writes and a crash when installing a disabled mod loader. [Release announcement](https://prismlauncher.org/news/release-11.1.0/)

For this repository, use the existing Nix package configuration. Prism's Java documentation distinguishes distributions that support automatic Java downloads from packages that bundle Java, including NixOS. Generic launcher setup instructions should not override that packaging choice without a reason. [Java installation](https://prismlauncher.org/wiki/getting-started/installing-java/)

No configuration changes, builds or deployments were made for this research.
