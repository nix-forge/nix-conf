# Forge CLI module research

## Scope and pinned support

This flake pins [Home Manager 03f4cd46](https://github.com/nix-community/home-manager/tree/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450) and [Nixpkgs 4382ed2b](https://github.com/NixOS/nixpkgs/tree/4382ed2b7a6839d4280a9b386db49cbc5907414d). The split between immutable program policy and mutable authentication state matters here. Tokens and account state must never enter the Nix store.

| Tool | Pinned Nix support | Recommendation |
| --- | --- | --- |
| GitHub CLI | Home Manager has [`programs.gh`](https://github.com/nix-community/home-manager/blob/03f4cd46bc1dd4f3a96da778d2ce9f7ce39dd450/modules/programs/gh.nix), including packaged extensions and a host-scoped Git credential helper. | Use it declaratively for non-secret settings. Keep `hosts.yml` unmanaged because it may contain account state. |
| GitLab CLI | This Home Manager revision has no `programs.glab` module. Nixpkgs packages [glab](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/gl/glab/package.nix). | Install it with `home.packages`; leave its configuration directory mutable so login can maintain credentials and metadata. |
| Azure CLI plus Azure DevOps | Nixpkgs exposes [`azure-cli.withExtensions`](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/az/azure-cli/package.nix) and ships the [azure-devops extension](https://github.com/NixOS/nixpkgs/blob/4382ed2b7a6839d4280a9b386db49cbc5907414d/pkgs/by-name/az/azure-cli/extensions-manual.nix). | Install a single `azure-cli.withExtensions [ azure-cli.extensions.azure-devops ]` package. Do not run `az extension add` or `az extension update`. |

These packages support both Linux and Darwin. Nixpkgs intentionally puts the Azure command and extension indexes in the store when using the default immutable configuration, while leaving authentication state mutable. This is the right division of responsibility for Nix.

## Shared policy

Keep packages, non-secret UX preferences, extension selection, and credential-helper wiring in shared modules. Put a machine's default host, organization, project, account selection, and any identity mapping in `homes/*/local/`. Keep PATs, OAuth tokens, client secrets, and `GH_TOKEN` or `AZURE_DEVOPS_EXT_PAT` out of Nix expressions, generated Home Manager files, permanent session variables, shell history, and aliases. Store-managed files are world-readable in the Nix store.

Use SSH for GitHub and GitLab by default, matching the existing Git and SSH module. It avoids an unnecessary token path for normal clone, fetch, and push. Retain HTTPS fallback only at exact host scope, never as a global replacement for the platform credential helper.

## GitHub CLI

Set `git_protocol = "ssh"`, carry the configured editor through, keep interactive prompts enabled, enable label colour when the terminal supports it, and disable telemetry. The [configuration reference](https://cli.github.com/manual/gh_config) documents those settings. The existing `programs.gh` module already enables its Git credential helper by default for only `https://github.com` and `https://gist.github.com`; this writes `gh auth git-credential` as a host-scoped helper rather than replacing the normal Git helper. That is the desired HTTPS fallback. Do not run `gh auth setup-git` from activation because Home Manager already owns that Git configuration. GitHub documents the same helper command in [`gh auth setup-git`](https://cli.github.com/manual/gh_auth_setup-git).

`gh auth login` uses the system credential store where available, then falls back to plaintext if it cannot use one. On Darwin that means Keychain. On Linux, make a Secret Service implementation available in the graphical session and verify with `gh auth status`; do not use `--insecure-storage`. GitHub says a fine-grained token used for automation belongs in a short-lived `GH_TOKEN` process environment rather than `--with-token`. [GitHub authentication guidance](https://cli.github.com/manual/gh_auth_login) documents both the secure-store preference and the fallback.

Use Nix-packaged extensions only. Home Manager places them in the expected extension directory, which prevents the CLI from cloning or downloading an unpinned extension at runtime. Keep `gh-poi` only if it is used. Extensions are code, not harmless configuration.

## GitLab CLI

Install `pkgs.glab`, but do not make `~/.config/glab-cli/config.yml` a Home Manager symlink. `glab auth login` needs to update it with host and keyring metadata. The Nixpkgs wrapper already turns off update checks and telemetry, so it needs no duplicate global environment settings. Disable only nonessential notices, such as the post-upgrade banner, through environment variables if their noise becomes a problem.

`glab` already defaults to SSH Git transport. For an HTTPS-only GitLab host, an explicit, exact-host `glab auth git-credential` helper is available after login. Do not configure it for SSH hosts and do not install it globally. GitLab's own login flow can offer that integration.

For authentication, use browser OAuth on a workstation and device flow on headless systems. GitLab documents Keychain on macOS and Secret Service on Linux as the normal storage backends. It warns that missing keyring support, `--insecure-storage`, and CI execution cause plaintext credentials in the configuration file. Re-running login migrates existing plaintext credentials to the keyring. [GitLab authentication documentation](https://docs.gitlab.com/cli/authentication/) and its [configuration reference](https://docs.gitlab.com/cli/config/) cover the behavior, `check_update`, `telemetry`, SSH default, and automatic companion-download settings. Avoid automatic download or execution of Duo and Orbit components.

## Azure CLI and Azure DevOps

Use the Nix-built package with the pinned Azure DevOps extension. Azure's normal dynamic-install behavior downloads wheels into `~/.azure/cliextensions`; that is convenient but the wrong trade for a managed system. Do not enable dynamic installs or Azure CLI autoupgrade. Nix already handles both updates through the flake lock. [Azure extension management](https://learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-overview?view=azure-cli-latest) documents dynamic installation and the mutable extension directory.

`~/.azure` must remain mutable and private. Azure stores its configuration there on both Linux and macOS, and Microsoft says its MSAL cache and service-principal entries are plaintext on both platforms. Do not manage this directory with Home Manager, copy it between machines, or put it under version control. Prefer interactive browser login for a person, `az login --use-device-code` when headless, managed identity where available, and least-privilege service principals for unattended automation. Microsoft recommends workload identities over user credentials for automation and requires MFA for user identities. [Azure authentication guidance](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest), [interactive login details](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively?view=azure-cli-latest), and the [MSAL cache warning](https://learn.microsoft.com/en-us/cli/azure/msal-based-azure-cli?view=azure-cli-latest) support this policy.

Use the mutable local config, not a Nix-linked file, for the following safe preferences:

```ini
[core]
collect_telemetry=no
survey_message=no
output=jsonc
disable_confirm_prompt=no
only_show_errors=no
```

`jsonc` remains structured while being readable in a terminal. Keeping confirmations and warnings preserves a useful safety check for commands that change cloud resources. Azure documents the configuration path, configuration keys, telemetry, output formats, logging, and confirmation behavior in its [configuration reference](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration?view=azure-cli-latest).

The Azure DevOps extension supports Azure DevOps Services, not Azure DevOps Server. It uses the active `az login` Microsoft Entra session, so prefer that over PATs. A guest user must use `az devops login`; automation may inject `AZURE_DEVOPS_EXT_PAT` for one process when unavoidable, but Microsoft recommends service connections with workload identity federation for pipelines. See the [Azure DevOps CLI quickstart](https://learn.microsoft.com/en-us/azure/devops/cli/?view=azure-devops) and [PAT authentication guidance](https://learn.microsoft.com/en-us/azure/devops/cli/log-in-via-pat?view=azure-devops).

Set a default Azure DevOps organization and project only in the relevant `homes/*/local/` module. The extension already detects organization, project, and repository from an Azure Repos checkout, with command flags taking precedence over detection and defaults. Leave that detection enabled. Do not enable its global `git pr` and `git repo` aliases: those generic names do not belong in a shared Git setup. [Azure DevOps detection and precedence](https://learn.microsoft.com/en-us/azure/devops/cli/auto-detect-and-git-aliases?view=azure-devops) documents both behaviors.

## Verification after implementation

Run these checks on both hosts after activation:

```sh
gh auth status
glab auth status
az extension show --name azure-devops
az devops --help
git config --show-origin --get-all credential.https://github.com.helper
```

The Git command should show the host-scoped GitHub helper and keep the platform helper as the fallback for unrelated HTTPS remotes. Verify that no token-bearing file is a Nix-store symlink, then authenticate interactively on each machine.
