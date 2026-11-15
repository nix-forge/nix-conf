# Windows ISO source for declarative VM builds

Research date: 2026-09-03

## Recommendation

Use the current Windows 11 consumer multi-edition x64 ISO and install Windows
11 Pro with a valid Pro license. Download the ISO once through Microsoft's
official page, record Microsoft's SHA-256 in Nix, and stage the verified file
locally for Packer or libvirt.

This does not meet the literal requirement that every clean build fetch the ISO
from a permanent public URL. No production Windows 11 client ISO does. Microsoft
publishes short-lived consumer download URLs, public evaluation media with
time-limited evaluation rights, and production Enterprise media behind
authenticated licensing portals. Those properties cannot be combined into one
official source.

Do not use Enterprise LTSC evaluation media as the persistent VM merely because
its current CDN URL is easy to fetch. Microsoft limits it to a 90-day
evaluation, and an expired guest shuts down every hour. Do not plan to convert
that installed evaluation into production later.

The practical declarative boundary is therefore:

```text
Public Git repository
  ISO filename, Windows release, language, edition and SHA-256
  Packer, Autounattend and libvirt definitions
                         |
                         v
Manual licensed input
  ISO downloaded from Microsoft and verified before import
                         |
                         v
Local Nix store, root-owned media directory, or private artifact cache
```

The recipe is reproducible once the exact ISO is present. ISO acquisition is a
licensed input with a verification step, not a reliable public fixed-output
derivation.

The desktop currently pins this exact manifest, observed on Microsoft's
download page on 2026-09-03:

```text
Release:      Windows 11 25H2
Media:        multi-edition x64, English (United States)
File:         Win11_25H2_English_x64_v2.iso
Install image: Windows 11 Pro
SHA-256:      768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3
Source page:  https://www.microsoft.com/en-us/software-download/windows11
```

Microsoft generated a direct `software.download.prss.microsoft.com` link for
that file, but the signed query string had a 24-hour expiry. Removing the query
string returned HTTP 403. The repository therefore records the stable source
page and exact content identity, not a dead-on-arrival direct URL.

## Comparison

| Channel | Public without authentication | Stable versioned ISO URL | Production use | Verdict |
| --- | --- | --- | --- | --- |
| Windows 11 consumer multi-edition | Landing page is public | No. Generated links last 24 hours | Yes, with the matching valid license | Best persistent VM source, but stage it manually |
| Windows 11 Enterprise evaluation | Public evaluation page and redirect | Current resolved CDN path contains a build, but Microsoft gives no retention promise | No. Evaluation is 90 days | Useful only for disposable image-pipeline tests |
| Windows 11 Enterprise LTSC evaluation | Public evaluation page and current direct CDN object | Closest match technically, but no permanence guarantee | No. Evaluation is 90 days | Do not use for the persistent VM |
| Windows Insider ISO | Program download flow | Builds and availability change | Preview use, builds expire | Unsuitable |
| Visual Studio subscription | No | Versioned downloads exist behind sign-in | Depends on subscription rights | Good licensed source if already entitled, but not public |
| Volume licensing and Microsoft 365 admin center | No | Cataloged media behind roles and sign-in | Yes, within acquired rights | Correct production Enterprise or LTSC source |
| Azure Marketplace image | No. Requires Azure account, subscription and permissions | Versioned Azure image URNs, not public ISO URLs | Depends on Azure and license entitlement | Cannot seed a local libvirt build directly |
| Exported Azure managed disk | No | Export uses an expiring SAS URL | Depends on the source entitlement | Adds cloud state and still lacks a permanent URL |

## Consumer multi-edition ISO

Microsoft describes the public x64 download as a multi-edition ISO intended for
boot media or a VM. The installed product key unlocks the matching edition.
The page also publishes language-specific SHA-256 values under "Verify your
download." This is the right media family for a normal Windows 11 Pro VM. See
the [Windows 11 download page](https://www.microsoft.com/en-us/software-download/windows11).

The same page states that generated download links remain valid for only 24
hours. A URL copied from that flow cannot be committed as Packer's long-lived
`iso_url`. The SHA-256 remains useful. It proves that a manually staged file is
the Microsoft file selected when the recipe was last updated.

Hash pinning and fetch stability solve different problems:

- A SHA-256 makes changed bytes fail closed.
- It does not keep a 24-hour URL alive.
- It does not preserve an old ISO after Microsoft removes it.

The host configuration should accept a local ISO path and expected hash. A
preflight command should calculate SHA-256 before Packer starts. If the file is
missing, the error should link to Microsoft's landing page and print the exact
expected filename and hash. Do not automate the web form through an unofficial
scraper.

## Enterprise and LTSC evaluation media

Microsoft's Evaluation Center currently offers Windows 11 Enterprise 25H2 and
Windows 11 Enterprise LTSC 2024 x64 ISOs. It publishes a hash document and
states that both are full-featured 90-day evaluations. No product key is needed
for the evaluation. If it is not activated or expires, Windows changes the
background, displays a persistent notification, and shuts down every hour. See
the [Windows 11 Enterprise Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise)
and its [download page](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise).

As of the research date, Microsoft's US English LTSC link redirects to this
public object:

```text
https://software-static.download.prss.microsoft.com/dbazure/
888969d5-f34g-4e03-ac9d-1f9786c66749/
26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_LTSC_EVAL_x64FREE_en-us.iso
```

The redirect's stable entry point is:

```text
https://go.microsoft.com/fwlink/?clcid=0x409&country=us&culture=en-us&linkid=2289029
```

The CDN object includes an exact build in its filename and currently accepts
unauthenticated requests. That makes it workable for disposable CI tests today.
Microsoft does not document that the resolved object will remain available
indefinitely. The `go.microsoft.com` redirect is a product pointer and may move
when Microsoft refreshes the evaluation. Pinning its current SHA-256 makes a
content change fail, but a removed object still breaks the build.

For an automated evaluation build, use Microsoft's reusable forwarding URL
rather than copying a session URL:

```text
Enterprise 25H2 evaluation, en-US x64
https://go.microsoft.com/fwlink/?linkid=2334167&clcid=0x409&culture=en-us&country=us
SHA-256: A61ADEAB895EF5A4DB436E0A7011C92A2FF17BB0357F58B13BBC4062E535E7B9

Enterprise LTSC 2024 evaluation, en-US x64
https://go.microsoft.com/fwlink/?linkid=2289029&clcid=0x409&culture=en-us&country=us
SHA-256: 67CEC5865EAA037A72DDC633A717A10A2BED50778862267223DDB9C60EF5DA68
```

Microsoft publishes those values in its current
[Enterprise evaluation hash document](https://go.microsoft.com/fwlink/?linkid=2334901).
The forwarding URL can change targets. The fixed hash turns that retargeting
into an intentional build failure instead of silently changing the image.

This is not a production LTSC download. Microsoft's LTSC lifecycle page says
Enterprise LTSC 2024 receives updates through October 2029 and is intended for
special-use devices. Microsoft also warns that support from applications and
tools designed for the General Availability Channel may be limited. See
[Windows 11 Enterprise LTSC 2024](https://learn.microsoft.com/en-us/windows/whats-new/ltsc/whats-new-windows-11-2024)
and the [LTSC lifecycle entry](https://learn.microsoft.com/en-us/lifecycle/products/windows-11-enterprise-ltsc-2024).

The production edition and the evaluation download are separate SKUs and
licensing channels. A URL that happens to expose the evaluation bytes does not
grant production rights.

## Evaluation conversion is not a deployment plan

Microsoft does not publish a supported Windows client path that turns the
Enterprise or LTSC Evaluation installation into the corresponding production
installation while preserving the VM.

The evidence is consistent:

- The Evaluation Center calls the media a 90-day evaluation and documents the
  hourly shutdown after expiry.
- Microsoft's Windows client edition-upgrade table lists Home, Pro,
  Pro for Workstations, Pro Education, Education, Enterprise and Enterprise
  LTSC. It does not list Evaluation as a supported source edition. See
  [Windows edition upgrade](https://learn.microsoft.com/en-us/windows/deployment/upgrade/windows-edition-upgrades).
- Microsoft's volume-download conversion section documents conversion for
  Windows Server evaluation and SQL Server evaluation. It does not give a
  Windows client evaluation conversion procedure. See
  [Download volume licensing products](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/download-vl-products?view=o365-worldwide#convert-from-evaluation-versions-to-volume-licensing-download-versions).

The safe rule is simple. Build a disposable evaluation VM to test the image
pipeline. Build the persistent VM again from licensed production media. Do not
install durable private state into an evaluation and hope that a later key will
remove its evaluation behavior.

## Production LTSC media

There is no official permanent public URL for the production Windows 11
Enterprise LTSC ISO.

Microsoft distributes volume-licensed ISO files through the Downloads page in
the Microsoft 365 admin center. Access requires a Volume License Administrator
or Product Download Manager role for the relevant license ID, and the customer
must have the applicable license. See
[Download volume licensing products](https://learn.microsoft.com/en-us/microsoft-365/commerce/licenses/download-vl-products?view=o365-worldwide).

Visual Studio downloads also require signing in to the subscription portal, and
the available software depends on subscription level. See
[Visual Studio subscription downloads](https://learn.microsoft.com/en-us/visualstudio/subscriptions/software-download-list)
and [subscription sign-in](https://learn.microsoft.com/en-us/visualstudio/subscriptions/find-my-subscription).

Windows IoT Enterprise LTSC does not provide a loophole. Microsoft says its
production media comes from the Volume License Service Center, Microsoft 365
admin center, Visual Studio Subscription, or an authorized OEM channel. It is
licensed for fixed-function specialized devices and is not a replacement for a
general-purpose Windows desktop. See
[Windows IoT Enterprise LTSC in Volume License](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/deployment/volume-license)
and [Windows IoT licensing](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/commercialization/licensing?view=windows-11).

If LTSC later becomes desirable, acquire the correct production ISO through its
licensed portal and place it in the same verified local-input workflow. Do not
switch to LTSC solely to reduce background features. A conservative Windows Pro
configuration can remove measured startup costs without taking on LTSC app
compatibility and licensing constraints.

## Windows Insider

Insider media is a poor source for a persistent appliance. Microsoft's Flight
Hub describes the ISO downloads as preview builds distributed by channel. The
build inventory changes continually, some experimental builds are not aligned
with a retail release, and older builds move to an archive. See the
[Windows Insider Flight Hub](https://learn.microsoft.com/en-us/windows-insider/flight-hub/).

Microsoft also says Insider Preview builds expire and may require an update or
clean installation. See
[Updating from an expiring Insider Preview build](https://learn.microsoft.com/en-us/windows-insider/build-expiration).
Preview media makes both operational stability and repeatability worse. It
offers no advantage for this VM.

## Official cloud images

Azure has versioned Marketplace image URNs, but these are Azure resources, not
public ISO artifacts. Windows client images require an eligible Azure or Visual
Studio subscription, and Marketplace use requires an Azure account,
subscription and purchase permission. See
[Use Windows client images in Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/client-images)
and [Azure Marketplace VM requirements](https://learn.microsoft.com/en-us/marketplace/purchase-vm-in-azure-portal#requirements).

Downloading an Azure managed disk does not create a permanent public source.
Microsoft requires an export operation that creates a Shared Access Signature
URL. That URL has an expiry, with a maximum of 60 days for managed disks and
snapshots. See
[Download a Windows VHD from Azure](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/download-vhd).

An Azure image can be a reproducible Azure deployment input when pinned by URN.
It is not an unauthenticated input for a local Packer or libvirt build. Building
in Azure and exporting a VHD would add cost, credentials, conversion steps and
another expiring URL without fixing the original requirement.

## Recommended repository interface

Keep source selection explicit:

```nix
windowsImage = {
  release = "25H2";
  mediaDescription = "Windows 11 25H2 multi-edition x64, English (United States)";
  downloadPage = "https://www.microsoft.com/en-us/software-download/windows11";
  imageName = "Windows 11 Pro";
  editionId = "Professional";
  isoFileName = "Win11_25H2_English_x64_v2.iso";
  isoSha256 = "768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3";
  locale = "en-US";
};
```

Do not put a generated CDN URL in the module. The build command should use the
stable local path `/var/lib/libvirt/boot/Win11_25H2_English_x64_v2.iso` and
verify it against `sha256` every time. A licensed private artifact store can
improve availability if its terms and access controls permit storing the ISO.
It should remain private. Do not mirror Windows installation media to a public
cache.

The user experience should be:

```text
$ windows-vm verify-media
Windows ISO missing.
Download Windows 11 x64 from:
  https://www.microsoft.com/en-us/software-download/windows11
Expected release: 25H2, en-US, multi-edition
Expected image: Windows 11 Pro
Expected SHA-256: 768984706B909479417B2368438909440F2967FF05C6A9195ED2667254E465E3
Stage as: /var/lib/libvirt/boot/Win11_25H2_English_x64_v2.iso
```

Once verification succeeds, Packer and libvirt remain fully automated. When
Microsoft publishes a new release, update the release, filename and hash in one
reviewed commit. Existing cached media continues to reproduce the old image.

## Final choice

For the persistent local libvirt VM, use Windows 11 Pro from the official
consumer multi-edition ISO. It matches ordinary desktop application support,
can be activated with an appropriate production license, and avoids Enterprise
or LTSC procurement unless those features are actually needed.

For automated tests of the unattended installer, the public Enterprise LTSC
evaluation ISO is acceptable if the recipe treats it as disposable and pins
both its resolved URL and Microsoft-published SHA-256. It must never become the
persistent production disk.

If a permanent, unauthenticated upstream URL remains a hard requirement, the
honest result is that no suitable production Windows 11 ISO exists. Change the
input requirement to "manually staged, hash-verified licensed media." Do not
weaken the licensing or operational design to make `nix build` fetch one more
file automatically.
