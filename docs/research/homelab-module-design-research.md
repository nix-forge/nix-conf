# Homelab module design research

Reviewed: 2026-09-30. Scope: placement, interfaces, security, and resource
policy for reusable NixOS services on a workstation and a small ARM host. This
note supports the current integration work; it is not a runtime audit.

## Answer

Keep reusable application behavior in `nix-homelab`. Keep each machine's disks,
credentials, network access rules, and hardware choices in the consuming host.
The same service module should work on either machine when its declared inputs
are available. Importing the flake should enable no applications. Profiles may
select a useful group, while each application remains independently selectable.
This is a repository design choice, consistent with the [NixOS module system's
typed options, conditional definitions, and assertions](https://nixos.org/manual/nixos/stable/#sec-writing-modules).

The current repositories already state this boundary in the root
[contribution guide](../../CONTRIBUTING.md) and the homelab
[contribution guide](../../nix-homelab/CONTRIBUTING.md). The homelab
[module entry point](../../nix-homelab/modules/default.nix) imports service groups;
its [profile module](../../nix-homelab/modules/profiles.nix) selects applications
and a desktop scheduling policy. The desktop's
[homelab host module](../../hosts/nixos/desktop/local/homelab/default.nix) supplies storage,
VPN, and credentials. These are observations from the working tree on the review
date, not claims that deployment has passed.

## Findings and sources

The [NixOS 26.05 manual](https://nixos.org/manual/nixos/stable/#sec-writing-modules),
retrieved 2026-09-30, recommends typed option declarations. It documents
`mkEnableOption`, conditional module definitions, and assertions that report
invalid combinations during evaluation. It also recommends a package option
where a module selects a package, instead of relying on an overlay for every
variant. For this project, add `homelab.*` options for shared policy or real
deployment variation. Keep application settings in native `services.*` options
when those options already express the need. An assertion is appropriate for a
required secret path, mount, or VPN policy that evaluation can actually verify;
it cannot establish that a runtime endpoint is healthy.

The [NixOS manual's secret-file examples](https://nixos.org/manual/nixos/stable/)
warn that literal credentials in Nix configuration can enter the world-readable
store. The [NixOS module type reference](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
describes `types.externalPath` but warns that later interpolation or derivation
use can still copy such a path into the store. Pass host-supplied runtime files
to native `passwordFile` or `environmentFile` options when available. When a
service needs another form, stage it at runtime with controlled permissions;
do not evaluate decrypted values into Nix. The existing homelab
[credential rules](../../nix-homelab/CONTRIBUTING.md) make this a project
requirement.

The [systemd v258 execution manual](https://github.com/systemd/systemd/blob/v258/man/systemd.exec.xml)
documents managed state, cache, log, and runtime directories. It also describes
filesystem restrictions such as `ProtectSystem=` and the interaction between
`DynamicUser=` and writable paths. Use those facilities through the NixOS
service unit where the upstream module permits them. Grant each service only
the state and device access it needs, then test the real startup path. A shared
data group or broad write path should follow an actual cross-service data flow,
not convenience. The [systemd v258 unit manual](https://github.com/systemd/systemd/blob/v258/man/systemd.unit.xml)
states that `RequiresMountsFor=` adds required mount and ordering dependencies
for a path. It supports a missing-media-mount failure policy, with the mount
declared by the host.

The [systemd v258 resource-control manual](https://github.com/systemd/systemd/blob/v258/man/systemd.resource-control.xml)
defines CPU and I/O weights as relative shares among siblings. It calls
`MemoryHigh=` the main memory control and `MemoryMax=` a last defense that can
trigger an in-unit out-of-memory kill. Put background tasks in a lower-priority
slice on a shared desktop, as the existing profile does. Do not copy a fixed RAM
limit from the desktop to a Raspberry Pi. Measure each host's pressure and task
latency before setting hard limits; a limit can make the user experience worse.

The [NixOS 26.05 test manual](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)
supports out-of-tree tests through `pkgs.testers.runNixOSTest`. It distinguishes
lightweight containers from virtual machines and notes that VMs can test
systemd filesystem namespacing. For service modules, evaluate the option
contract first, then use VM tests for startup, failed mounts, network access,
credentials, and recovery behavior. Native ARM hardware, peripherals, and
multicast discovery still need separate runtime checks.

## Implication for this repository

Move a host-local service into `nix-homelab` when its application behavior can
be expressed with inputs instead of a host name. Keep host files thin: select
the application, provide secret file paths, choose storage and network
exposure, and set hardware-specific access. Keep application-specific helpers
beside the owning module. Share a helper only after two consumers need the same
behavior and one option contract can cover both.

For each move, check that importing the module alone starts nothing, that a
missing required input fails clearly, and that the enabled service's actual
startup and failure paths pass. Test reverse proxy access separately from
loopback binding and firewall policy. Record backup and restore ownership before
moving stateful services; evaluation cannot prove recovery.

## Validation and limits

This was a read-only source review on the local Linux checkout, plus the cited
NixOS 26.05 and systemd v258 documentation retrieved 2026-09-30. No Nix
evaluation, package build, VM test, Raspberry Pi run, restore, or activation was
performed for this note. The working tree contains concurrent changes, so the
observed layout is a snapshot rather than a fixed release.
