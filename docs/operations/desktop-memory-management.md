# Desktop memory management

The desktop configures encrypted swap, systemd-oomd, and separate memory limits
for the Nix daemon and interactive applications. Temporary task helpers use
`codex-task run COMMAND [ARGS...]`; finish task-owned helpers when their work ends.

Run builds and checks directly with the host's configured compiler parallelism.
Full desktop system builds run on desktop; use `just desktop-build` or
`just desktop-deploy` from another host. See [AGENTS.md](../../AGENTS.md).

Memory and swap settings are owned by the desktop system and home modules.
Inspect the generated `system.build.desktopMemoryPolicy` output for effective
units and backup policy. Module assertions validate setting combinations;
runtime acceptance remains an operator task.
