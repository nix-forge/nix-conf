# Homebridge and Apple Home integration choices for a small Pi

Reviewed: 2026-10-01. Scope: a 2 GiB Raspberry Pi running NixOS and Homebridge,
with representative Arlo, LG ThinQ, Samsung, Sony, Levoit, Blueair, Aura,
Skylight, Ting, and PlayStation devices. Model labels, account access, and
runtime pairing must be verified on the physical devices. This is a design and
source review, not a claim that every device is paired.

## Recommended paths

| Device | Preferred path | Gate before enabling |
| --- | --- | --- |
| Arlo cameras and doorbell | Trial Scrypted Arlo Cloud and HomeKit plugins on the Pi, keeping cameras on ordinary Wi-Fi | Confirm cloud login, each camera stream, Home pairing, and motion events. |
| Aura frame | Aura's own app and documented photo import | No supported HomeKit control path established. |
| LG WM9000HVA washer and DLE7300VE dryer | Pilot the packaged LG ThinQ fork | Confirm both in ThinQ, account login method, and useful status entities. |
| Sony KD-50X85J TV | Pair directly with Apple Home | Complete on-screen HomeKit pairing. |
| Samsung S90H TV | Homebridge Samsung Tizen plugin | Test TV authorization and routed LAN control. |
| Levoit Vital 200S | Packaged Homebridge VeSync plugin | VeSync account authentication and device discovery remain. |
| Blueair Blue Pure 511i Max | Packaged Homebridge Blueair purifier plugin | Blueair account authorization and device behavior remain to be tested. |
| Ting monitor | Keep official Ting app and alerts | Third-party status is optional and cannot replace hazard response. |
| Skylight calendar | Sync its source calendar | A display is not itself a HomeKit accessory. |
| PlayStation 5 | Leave out of Homebridge | The accessory's limited utility does not justify console authorization and another Home pairing. |

## Evidence behind the choices

[Arlo's Apple Home instructions](https://www.arlo.com/en_gb/support/faq/connectivity-and-integrations/how-do-i-connect-my-arlo-camera-to-apple-homekit)
require supported cameras to connect through a SmartHub for native HomeKit. For
cameras kept on ordinary Wi-Fi, the selected trial is
[Scrypted's Arlo plugin](https://github.com/scryptedapp/arlo) with Scrypted's
HomeKit and Rebroadcast plugins. Arlo Cloud remains in the video path, and the
plugin needs an email or SMS second factor. Arlo permits one stream type at a
time, so test one camera before adding the others. The [camera report card](https://github.com/koush/scrypted/wiki/Camera-Support-Report-Card)
flags motion reliability and missing two-way audio. The [Pi hardware guidance](https://docs.scrypted.app/server-hardware.html)
supports basic streaming but not NVR or software motion detection on this
hardware. Leave recording and prebuffering off, then measure load and latency.

Apple Home can show live video and notifications without recording. HomeKit
Secure Video adds encrypted clips, Activity Zones, and object or face
classification. Apple's newer Home intelligence can group notifications; video
descriptions and natural-language clip search require recorded clips, suitable
current devices, and eligible iCloud+. Apple's [iPhone camera guide](https://support.apple.com/en-ca/guide/iphone/iph7bc5df9d9/ios)
and [tvOS 27 release notes](https://developer.apple.com/documentation/tvos-release-notes/tvos-27-release-notes)
describe those gates; the release notes specify an iCloud+ plan of at least
2 TB for Apple Intelligence for Home. None of the clip features is enabled by
this live-only trial, and Scrypted's Arlo path has not been proved to satisfy
them.

The original [LG ThinQ Homebridge project](https://github.com/nVuln/homebridge-lg-thinq)
documents washer and dryer support with limited controls. Its source contains a
2.0.0 manifest, but npm still published 1.8.11 as the stable release when checked
on 2026-09-29; that release excludes Node 24. The packaged
[@mp-consulting fork](https://github.com/mp-consulting/homebridge-lg-thinq)
declares Node 24 and Homebridge 2 support. Its [changelog](https://github.com/mp-consulting/homebridge-lg-thinq/blob/main/CHANGELOG.md)
records LG sign-in and washer status fixes. It monitors washer and dryer state,
but its README does not claim direct laundry control. The [official Home
Assistant LG ThinQ integration](https://www.home-assistant.io/integrations/lg_thinq)
uses ThinQ Connect and a personal access token, and is a better fit if a larger
Home Assistant deployment is already justified. It does not by itself establish
which laundry entities Apple Home can display. LG identifies the
[washer](https://www.lg.com/us/business/washers/lg-WM9000HVA-front-load-washer)
and [dryer](https://www.lg.com/us/washers-dryers/lg-dle7300ve-electric-dryer)
as connected models.

Sony [specifies HomeKit support for KD-50X85J](https://www.sony.com/electronics/support/televisions-projectors-lcd-tvs-android-/kd-50x85j/specifications).
[Sony's setup instructions](https://www.sony.com/electronics/support/televisions-projectors-lcd-tvs-android-/xbr-65x950h/articles/00240542)
and [Apple's accessory troubleshooting](https://support.apple.com/en-au/126198)
call for the phone and TV to be on the same network during pairing. When a TV
advertises its unpaired HomeKit service and its pairing port is reachable from
another subnet, a generic network block is not established. A temporary
same-Wi-Fi pairing test can distinguish a cross-subnet setup issue from a TV
or account issue. If it fails on the same Wi-Fi, check the TV's AirPlay and
HomeKit settings, Sony Smart TV Services privacy setting, software version,
and restart before resetting the TV's HomeKit pairing state.
For the Samsung TV, [Apple distinguishes AirPlay from Home app pairing](https://support.apple.com/en-gb/104998).
[Samsung identifies S90H as a 2026 Tizen 10 model](https://developer.samsung.com/smarttv/develop/specifications/tv-model-groups.html),
and [Homebridge Samsung Tizen](https://github.com/tavicu/homebridge-samsung-tizen)
claims support for 2017 and newer Tizen televisions. That is a good plugin
candidate, but the S90H still needs an actual authorization test. The package is
pinned in `pkgs/`; TV pairing data stays in protected Homebridge state.

The packaged [homebridge-tsvesync](https://github.com/mickgiles/homebridge-tsvesync/blob/v1.6.1/README.md)
explicitly lists Vital 200S power, fan, mode, air quality, and filter state.
Its upstream tag has no dependency lockfile; the package carries a generated
lock with a fixed Nix dependency hash. The [other Levoit plugin](https://github.com/RaresAil/homebridge-levoit-air-purifier/releases/tag/v3.1.1)
added Vital support, though its README still has an older Core-only table.
[Home Assistant's VeSync integration](https://www.home-assistant.io/integrations/vesync)
supports another route if Home Assistant is already justified. The
[newer Blueair plugin](https://github.com/kovapatrik/homebridge-blueair-purifier)
lists Blue Pure 511i Max as a tested model. It uses the Blueair cloud account;
its README warns that API PM2.5 values can be inaccurate. The personal package
pins release 1.2.1, updates the vulnerable runtime `lodash` dependency, and
removes logs that could expose account data and API tokens. The
[older Blueair fork](https://github.com/fjs21/homebridge-blueair) supports
other generations but has much less recent maintenance and does not list this
model. Account authorization and behavior still require a device test.

[Aura's documented setup](https://help.auraframes.com/hc/en-us/articles/18972006839575-Can-Aura-Frames-be-used-without-a-smart-device-phone-tablet)
uses its app. [Skylight documents calendar synchronization](https://www.skylightframe.com/lp/calendar-syncing/)
with standard calendar providers. [Ting describes](https://www.tingfire.com/get-ting/)
continuous official monitoring and human hazard response; an unofficial cloud
status client is not a replacement. The packaged optional
[Homebridge PlayStation plugin](https://github.com/kopiro/homebridge-playstation)
needs PSN and console pairing. Its upstream discovery uses broadcast; the
personal package adds a `deviceIp` option and login CLI argument backed by
[PlayActor's directed discovery](https://github.com/dhleong/playactor/blob/main/src/discovery.ts)
for routed networks. Directed discovery still needs a gateway path to the
console and a real pairing test. The package remains available but the Pi no
longer selects it. The non-camera devices do not need another
service on the Pi to keep their normal vendor functions.

## Deployment rules and remaining tests

Keep the Pi on upstream Homebridge and its existing LAN-only HTTPS UI. Run the
pinned official Scrypted Lite image as a separate live-view-only service with
its own protected state and LAN-only HTTPS proxy. Store Homebridge
plugin code as pinned Nix packages when selected; keep tokens, TV authorization,
HomeKit pairing identity, and other mutable state under protected Homebridge
storage. The [NixOS module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/homebridge.nix)
uses a writable plugin directory. The reusable declarative plugin module links
package outputs there and refuses to replace a mutable directory with the same
name. Updates to those packages belong in Nix, not the Homebridge UI.

Enable one platform at a time and check vendor login, accessory behavior, service
memory, and logs. Use [Homebridge child bridges](https://github.com/homebridge/homebridge/wiki/Child-Bridges)
only where isolation has a demonstrated benefit: each adds a separate Node
process and HomeKit pairing port. A TV or cloud plugin needs a routed connection
from the Pi to its device or vendor API; mDNS discovery alone does not establish
this. Package builds and the Pi system closure validate installation, not
accessory pairing. Blueair, LG, and VeSync authorization remain to be completed
in protected mutable state.
