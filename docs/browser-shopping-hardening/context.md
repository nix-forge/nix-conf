# Browser shopping hardening evidence context

Analysis date: 2026-09-02

Source root: `/Users/ianmh/Developer/personal/nix-conf`

Target revision: `9d39e12d9a394c6459e98f3b58d08f8069723710`

Source drift is present because the working tree contains uncommitted browser-module changes. This proposal describes the inspected working tree rather than claiming an immutable deployed state.

The collection digest is the SHA-256 of the ordered SHA-256 manifest below: `5dbfb5e2e1c0c5ea6432b55583bd7af979830a99224ae779fa54e1016ff2c5df`.

| Evidence | File | SHA-256 | Purpose |
| --- | --- | --- | --- |
| `E001` | `docs/browser-shopping-profile-research.md` | `3ab0e8a0c5d92ef86b84880967f20cf76764351b8a0f834534b96ba7a325d049` | Primary-source research on Rakuten, Firefox isolation, Safari profiles, and extension choices |
| `E002` | `modules/home/browsers/shared/extensions.nix` | `50a5495dc4515d5e2ec40873be2a700bc697e938f1f4c6ec2d484d4ebdeeda77` | Shared extension schema and forced uBlock Origin declaration |
| `E003` | `modules/home/browsers/firefox/default.nix` | `2be2aa9e44b1b6faae6b3af56785ae1681f00b9d2012bb868a2929cd19876144` | Firefox application-wide extension policy adapter |
| `E004` | `modules/home/browsers/zen/default.nix` | `cab7af3255c4b1804111c38d87a25c44b1059ee6184f6f40cb48f89f604ffead` | Zen application-wide extension policy adapter |
| `E005` | `homes/shared/local/browsers/extensions.nix` | `bc24b4208604adcfe5d396618dc4b0512c1726095fbba1582d575559c8b2fe6c` | Current personal shared and Firefox-only extension membership |

The external evidence is linked and summarized in `E001`. It includes current first-party documentation from Rakuten, Mozilla, Apple, Bitwarden, uBlock Origin, and the pinned Home Manager source.
