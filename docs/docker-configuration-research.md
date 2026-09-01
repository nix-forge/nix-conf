# Docker configuration research

## Recommendation

Keep Docker rootless on NixOS and make it an explicit, on-demand user service.
Do not enable the rootful daemon or add the user to the `docker` group. The
rootful socket is reliably socket activated on NixOS, but access to it grants
root-level control of the host. That is too large a trade for a personal
workstation whose Docker workload is development and local services. Docker
rootless mode keeps both `dockerd` and containers out of the root account.
It still relies on unprivileged user namespaces, so it is containment, not a
substitute for careful image and container policy.

The current rootless NixOS module starts `docker.service` from every eligible
user manager's `default.target`, restarts it on failure, and does not provide a
socket unit. With the desktop user's lingering manager, that means the daemon
starts at login and stays resident. Disable that `WantedBy` relationship for
this host and provide Home Manager commands that start, stop, and inspect the
service. Use a `docker-up` wrapper around `systemctl --user start
docker.service`, with matching `docker-down` and `docker-status` commands.
This keeps the daemon at zero CPU and near-zero memory when Docker is idle.
Stopping it does not delete images, volumes, or BuildKit cache.

Use one cross-platform Home Manager module for the Docker CLI, Compose and
Buildx plugins, Docker client settings, contexts, completions, and the UX
wrappers. Put NixOS-only daemon settings in a general
`modules/nixos/virtualisation/docker.nix` module. Keep the workstation user
condition, cgroup-controller delegation, and personal resource limits in
`hosts/nixos/desktop/local/`. Keep the Darwin Colima profile and any local
service stack choice in `homes/macbook-pro-m4/local/`. Home Manager owns the
client, NixOS owns the Linux daemon and kernel prerequisites, and Colima owns
the macOS VM.

## What is present now

The repository already avoids the rootful NixOS daemon. It enables rootless
Docker, exports `DOCKER_HOST`, enables user lingering, limits the global Docker
unit to `ianmh`, uses the `local` log driver, and enables live restore. The
problems are lifecycle and macOS path ownership.

`virtualisation.docker.rootless` declares a user service wanted by
`default.target` and restarts it unconditionally. The desktop then enables
linger. Docker therefore runs after a user login even when no Docker client or
container is wanted. [The pinned NixOS module](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/nixos/modules/virtualisation/docker-rootless.nix#L60-L96)
shows the generated service.

The Home Manager profile is on state version 25.05. At that version the pinned
Colima module stores its state in `~/.colima`, unless `colimaHomeDir` is set.
The Karakeep module hard-codes `~/.config/colima/default/docker.sock`. That
path will not match the generated default profile. Derive the socket from
`services.colima.colimaHomeDir` and avoid a second definition. This preserves
the existing `~/.colima` VM and its local images and volumes for a 25.05 Home
Manager profile. [The pinned Colima module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/services/colima.nix#L17-L40)
defines the version-dependent default and
[its service implementation](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/services/colima.nix#L249-L333)
shows that `isService = true` starts Colima at load and keeps it alive.

For a laptop, the Colima profile should stay active as a Docker context but not
be a service. A manual `docker-up` wrapper should run `colima start default`,
then wait for `docker info`; `docker-down` should run `colima stop default`.
This releases the VM's reserved CPU and memory. Do not run Kubernetes in that
profile. A local application with its own launchd agent, such as Karakeep, must
be opt-in and should start Colima itself if it remains supported. It otherwise
defeats lazy startup.

## Linux daemon design

### Security boundary

Rootless Docker is the right default. Docker says it runs both the daemon and
containers as a non-root user, reducing the impact of daemon and runtime flaws.
It requires `newuidmap` and `newgidmap`, plus at least 65,536 subordinate UIDs
and GIDs for the account. [Docker's rootless documentation](https://docs.docker.com/engine/security/rootless/)
has the prerequisites and limits. NixOS supplies the rootless daemon as a user
unit and uses `/run/wrappers` for the mapping helper. The NixOS option is the
correct system-level owner for this feature, not Home Manager.

Do not turn on a rootful fallback or grant the `docker` group. Docker's own
installation guide says that group grants root-level privileges. A controller
of the rootful daemon can mount host paths into a container. Keep the Docker
API on the per-user Unix socket. Never bind an unauthenticated TCP API,
particularly port 2375. If remote use becomes necessary, use a Docker SSH
context or mutually authenticated TLS. [Docker's socket guidance](https://docs.docker.com/engine/security/protect-access/)
describes those transports.

Enable the NixOS system prerequisite `security.allowUserNamespaces = true` and
the normal subordinate-ID setup that the NixOS rootless module expects. That
weakens a host-wide kernel restriction, so it belongs in the desktop's local
security policy with a comment explaining why. It should not be in a shared
Home Manager module.

Keep Docker's default seccomp and AppArmor policy. Docker calls its default
seccomp profile an allowlist and advises against replacing it. The profile
blocks dozens of system calls while retaining broad compatibility. [Docker's
seccomp documentation](https://docs.docker.com/engine/security/seccomp/) is
clear on that point. Set the daemon-wide `no-new-privileges` default. Do not
add `--privileged`, host networking, host PID namespace, Docker socket mounts,
or writable host bind mounts in reusable Compose examples. Each is a
workload-specific escape hatch and belongs in the local workload definition.

Set `default-network-opts.bridge.com.docker.network.bridge.host_binding_ipv4`
to `127.0.0.1` for new Docker bridge networks. It makes an omitted host address
in a published port bind to loopback rather than every interface. Docker
documents this daemon option in its [dockerd reference](https://docs.docker.com/reference/cli/dockerd/).
Compose files should still state `127.0.0.1:HOST:CONTAINER` explicitly when a
service is meant to remain private.

### Resource control and performance

Rootless Docker honors container CPU, memory, and PID limits only with cgroup
v2 and systemd. Docker documents that a normal user service commonly receives
only the memory and PID controllers. To let containers use `--cpus`, I/O,
cpuset, and memory limits, delegate `cpu cpuset io memory pids` from the
system-level `user@.service` to user managers. Put that override in
`hosts/nixos/desktop/local/security-virtualization.nix`: it affects every local
user manager and is personal-host policy. The rootless Docker service already
has `Delegate=true`; it cannot delegate controllers it was never given.
[Docker's rootless cgroup guidance](https://docs.docker.com/engine/security/rootless/tips/#limiting-resources)
explains both requirements.

Do not set a storage driver without a measured reason. Docker chooses the right
modern driver for a fresh installation, and changing a configured driver makes
existing images and containers inaccessible. Docker's rootless data directory
must remain on local storage, not NFS. Named volumes are a better choice than
bind mounts for write-heavy database data. [Docker's storage-driver guidance](https://docs.docker.com/engine/storage/drivers/)
covers the migration risk.

Use the `local` log driver with string-valued rotation options:

```nix
{
  "log-driver" = "local";
  "log-opts" = {
    "max-size" = "10m";
    "max-file" = "3";
  };
}
```

Docker recommends `local` for general non-Kubernetes workloads. It rotates by
default and uses an efficient on-disk format. Daemon defaults affect newly
created containers, so recreate a service after changing the driver. [Docker's
logging documentation](https://docs.docker.com/engine/logging/configure/) also
requires every `log-opts` value in daemon configuration to be a string.

Keep `live-restore = true` for an explicitly started local service. It avoids
stopping standalone containers on an ordinary daemon restart. It does not make
major upgrades or daemon-level network and storage changes seamless, and a
daemon that stays down can eventually block a container's logging pipe. It is
incompatible with Swarm, which this setup does not need. [Docker's live-restore
documentation](https://docs.docker.com/engine/daemon/live-restore/) gives the
limits.

Do not install a periodic prune timer by default. A scheduled Docker client
would wake the rootless daemon, work against the idle requirement, and a broad
prune can remove useful local cache. Provide an explicit `docker-clean` command
that reports reclaimable space first and requires a deliberate flag to prune
images, builders, or volumes.

### Build behavior

Install Buildx as a Docker CLI plugin and use `docker buildx build` or Compose
v2. BuildKit skips unused stages, runs independent stages in parallel,
transfers only used and changed build context, and manages its cache
automatically. [Docker's BuildKit overview](https://docs.docker.com/build/buildkit/)
documents those behavior changes. Do not enable BuildKit insecure entitlements
such as `network.host`, `security.insecure`, or `device`; Docker ships them off
by default. [The BuildKit configuration reference](https://docs.docker.com/build/buildkit/toml-configuration/)
lists them explicitly.

For images that leave the workstation, Buildx can emit SBOM and provenance
attestations. Use those per release build with `--sbom` and
`--provenance=mode=max`, rather than emitting metadata for every scratch build.
The default Engine image store does not retain attestations locally. They persist
when pushed to a registry or when the containerd image store is used. [The
Buildx reference](https://docs.docker.com/reference/cli/docker/buildx/build/)
documents both behavior and the flags.

## Home Manager and Darwin design

Home Manager's `programs.docker-cli` should be the sole owner of
`DOCKER_CONFIG`, `config.json`, and named Docker contexts. It supports typed
configuration and writes contexts under its selected config directory. [The
pinned module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/docker-cli.nix#L23-L115)
shows the state-version-dependent directory. Do not set a raw `DOCKER_HOST` and
a competing client context when a context can describe the same endpoint. An
environment variable takes precedence and makes switching contexts confusing.

For NixOS, retain a rootless Docker context and do not export a competing
`DOCKER_HOST`. For Darwin, let an explicit `colima start` activate its own
context and do not leave a persistent Docker endpoint in the login
environment. The Colima Home Manager module supports a profile that is active
without becoming a resident service. It also supports no active profile, which
is useful if remote SSH contexts become the main use case. [Its profile options](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/services/colima.nix#L64-L152)
document both controls.

Use Apple Virtualization and VirtioFS on Apple Silicon. Keep Kubernetes off,
agent forwarding off, nested virtualization off, and expose no VM address by
default. Start with a modest VM allocation. Four CPUs and 8 GiB reserve too
much for an idle laptop even if Colima does not start at login. The initial
profile should use 2 CPUs, 4 GiB memory, and a 60 GiB disk, then increase those
numbers in the MacBook local file only if a measured build or workload needs
them. Limit writable mounts to project directories. Prefer named volumes for
databases and other write-heavy data.

`programs.lazydocker` is a good optional terminal UI. Its Home Manager module
already uses `docker compose`, which matches the plugin-based Compose command.
[The pinned module](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/lazydocker.nix#L23-L58)
shows the generated setting. Keep it from starting the runtime automatically.

## Workload rules

The daemon cannot make an unsafe Compose service safe. Put application-specific
settings next to the workload, not into global daemon configuration. A strong
default Compose service has a pinned image digest, a non-root `user` where the
image supports it, `read_only: true`, a `tmpfs` for writable paths,
`security_opt: ["no-new-privileges:true"]`, dropped capabilities, explicit
memory, CPU and PID limits, a health check, and a loopback-only port mapping.
Avoid mutable `release` and `latest` tags for services that hold user data.

The current Karakeep definition is disabled, but it deserves separate review
before being enabled. It uses mutable image tags, grants Chrome a
`--no-sandbox` flag, and has a macOS launchd agent designed to keep the stack
alive. Browser automation sometimes requires a trade, but that trade should be
an explicit local opt-in. Never expose the Chrome remote-debugging port on the
host.

## Verification after implementation

On NixOS, after a rebuild and a fresh login:

```sh
systemctl --user is-enabled docker.service
systemctl --user is-active docker.service
docker-up
docker info --format '{{.SecurityOptions}} {{.CgroupDriver}}'
docker run --rm --memory=128m --pids-limit=64 alpine true
docker-down
systemctl --user is-active docker.service
```

The first state should be disabled and inactive. `docker-up` should make the
daemon active. `docker info` should report rootless security options and the
systemd cgroup driver. The constrained test should work on cgroup v2 after the
controller delegation.

On Darwin, after a Home Manager activation and reboot:

```sh
colima status
docker-up
docker context show
docker info
docker-down
colima status
```

Colima should be stopped before `docker-up` and after `docker-down`. Confirm
the active Docker context uses the same socket path that the generated Colima
profile exports. Build a small multi-stage image twice to verify BuildKit cache
reuse. Start a test Compose service with `ports: ["8080:80"]` and confirm it
is only reachable on `127.0.0.1` on Linux.
