# Codex computer use on Linux

Research date: 2026-09-05. Documentation/source review only; no third-party tool was installed or tested on this desktop, and no configuration was changed.

## Official status and expected release

OpenAI's Linux preview guide explicitly says Computer Use is unavailable on Linux and will be added in a future release. It supplies no release date. As of this research date, no public date was found in the official documentation checked. Current native Computer Use is documented for macOS and Windows. This is an upstream platform limitation, not evidence of a missing Nix dependency or a setting that should be forced on. [Linux preview limitations](https://learn.chatgpt.com/docs/linux/linux-app), [Computer Use](https://learn.chatgpt.com/docs/computer-use)

NixOS is outside OpenAI's formally supported distribution list, and native Wayland is still experimental. A future general Linux release therefore should not be assumed to guarantee Hyprland support immediately; its actual compositor requirements will need checking when published. This is a compatibility caution, not a prediction of the implementation. [Linux support policy](https://learn.chatgpt.com/docs/linux/linux-app)

## Best first step: official browser integration

Browser automation is separate from arbitrary desktop-app control. OpenAI's Linux guide links to its browser extension setup. The built-in browser uses a separate profile; the extension operates existing browser sessions and offers per-site approvals. Prefer the built-in browser for local web development and isolated sign-ins, and the extension only where an existing browser session is needed. Do not grant blanket access to all sites. Availability may depend on rollout and workspace policy, and neither integration was tested on this NixOS host in this research turn. [Built-in browser](https://learn.chatgpt.com/docs/browser), [browser extension](https://learn.chatgpt.com/docs/chrome-extension), [Linux next steps](https://learn.chatgpt.com/docs/linux/linux-app)

Third-party MCP integrations are supported by the desktop app and share host configuration with Codex CLI and the IDE extension. They can provide additional tools without modifying the packaged application, but do not inherit a promise of native Computer Use's per-app controls. [MCP integration](https://learn.chatgpt.com/docs/extend/mcp)

OpenAI also provides an API computer-use guide for developers who supply their own browser or desktop execution environment. This is a separate integration path, not a switch that enables the Linux desktop plugin. Its safety guidance recommends isolation, limited access, confirmation of consequential actions, cancellation, and outcome verification. [API computer-use guide](https://developers.openai.com/api/docs/guides/tools-computer-use)

## Third-party alternatives

These are optional additions, not substitutes for checking Codex's own browser integration first. They do not turn on OpenAI's native Computer Use feature.

### Browser automation: Microsoft Playwright MCP

Playwright MCP exposes browser actions through structured accessibility snapshots and has documented Codex configuration. It supports Linux, a separate persistent profile, an ephemeral `--isolated` profile, headless operation, and an explicit browser executable. It does not control arbitrary Linux desktop applications. Its project includes tests and is maintained in Microsoft's Playwright organization. [Playwright MCP](https://github.com/microsoft/playwright-mcp)

Assessment: a good fallback for web development and browser workflows. Prefer a pinned server/browser pairing, a dedicated profile, stdio transport, and task-scoped access. On NixOS, browser packaging needs explicit validation instead of assuming the upstream downloaded browser works. Headless browser actions avoid dependence on Hyprland's screen-input protocols; structured element targeting also avoids physical monitor coordinates. These are implementation recommendations, not a tested configuration.

Microsoft explicitly warns that the server is not a security boundary. Origin restrictions are not sufficient isolation, and attaching the extension to a logged-in browser grants access to that session. An isolated browser profile does not isolate the host filesystem or network. [Playwright security and configuration](https://github.com/microsoft/playwright-mcp/blob/main/README.md)

### Native desktop candidate: Cua Driver

Cua Driver documents Codex MCP integration and Linux support. Its upstream Nix infrastructure builds the driver and runs Rust, policy, and Wayland checks. This makes it a credible project to evaluate, rather than a one-off screenshot-and-click script. [Codex integration](https://cua.ai/docs/use-cua-with/codex), [Nix build and test setup](https://github.com/trycua/cua/blob/main/nix/cua-driver/README.md)

It is not yet a recommendation for this daily Hyprland desktop. The project's accepted Linux evidence covers X11/Openbox and Sway, with separate GNOME/KDE limitations; it explicitly does not equate another compositor with tested Sway behavior. Native Wayland raw background input has limitations, and cursor preservation remains unproven in the published matrix. [Behavioral evidence ledger](https://github.com/trycua/cua/blob/main/libs/cua-driver/docs/action-support.md)

The earlier wrong-workspace screenshot bug is **fixed**, not still open: merged PR #3200 makes unproven window capture fail closed. That is a safety improvement, not complete Hyprland capture support. Issue #3399 remains open for per-window screenshots failing on Hyprland with Cua Driver 0.22.1; PR #3052 for Hyprland capture/input remains draft. The report involves scale 1.5, but does not establish scaling as the cause. [Merged capture fix](https://github.com/trycua/cua/pull/3200), [current Hyprland report](https://github.com/trycua/cua/issues/3399), [draft Hyprland support](https://github.com/trycua/cua/pull/3052)

Assessment: suitable for an explicitly supervised experiment after pinning a release and verifying the exact applications, capture identity, focus behavior, Unicode input, and emergency stop. Do not bypass truthful capture refusals just to make a demo work.

### Isolated Linux GUI experiments: Cua Sandbox

Cua documents local Linux VMs through QEMU and Linux containers through Docker. Its runtime matrix carefully distinguishes SDK/runtime selection from a successfully boot-tested guest. The CLI's `cua serve-mcp` exposes sandbox management and GUI control to an MCP client. [Runtime support](https://cua.ai/docs/reference/sandbox-sdk/runtime-support), [MCP server](https://cua.ai/docs/reference/cua-cli/mcp-server)

Assessment: a disposable VM is a more sensible place to evaluate full Linux GUI control than a signed-in personal desktop. Start without host-home mounts, host display/input sockets, SSH-agent forwarding, or personal browser profiles. Explicitly grant only needed tools and inspect the resulting tool list. The documented MCP permission parser grants everything for an empty or wholly unrecognized permission list, so a misspelled restriction is not safe. No local boot or Codex-to-sandbox connection was tested here. [Permission behavior](https://cua.ai/docs/reference/cua-cli/mcp-server)

## Why Hyprland needs care

Hyprland's current portal manifest includes Screenshot, ScreenCast, GlobalShortcuts, and InputCapture, but not RemoteDesktop. Having screen sharing therefore does not establish that a generic portal-based remote-input tool will work. [Portal implementation manifest](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/master/hyprland.portal)

Direct input workarounds can broaden authority. For example, `ydotoold` needs `/dev/uinput` access, usually requiring root; it is an input-injection tool, not an app-scoped approval system. Assessment: do not give a permanent generic desktop-control bridge this authority merely to fill the native feature gap. [ydotool runtime requirements](https://github.com/ReimuNotMoe/ydotool#notes)

## Recommendation

Use browser-scoped automation for browser work. Keep whole-desktop Linux automation experimental and isolated for now. If host-native Cua Driver is evaluated later, require a pinned, reproducible Nix package and application-specific end-to-end validation before enabling it on the daily session. This recommendation reflects the documented compositor gaps and security boundaries above, not a claim that Linux computer use is impossible.
