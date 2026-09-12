# Build a Nix environment you understand

nix-conf configures a NixOS desktop and an Apple Silicon Mac using Home Manager
and reusable modules. This guide starts with a small environment you can build
without access to either machine or its secrets.

[Start the tutorial](guide/start-here.md) · [Browse reusable recipes](guide/git.md) · [See the architecture](guide/architecture.md)

## Choose your starting point

| You want to… | Start with |
| --- | --- |
| Try Nix configuration without changing your account | [Build the starter](guide/first-configuration.md) |
| See a configured system boot | [Run the disposable NixOS VM](guide/virtual-machine.md) |
| Practice in a graphical Linux session | [Run the Sway demo](guide/graphical-demo.md) |
| Build a small Apple Silicon system configuration | [Try the Darwin example](guide/darwin-example.md) |
| Improve an existing Home Manager environment | [Git](guide/git.md), [file search](guide/file-search.md), or [the prompt](guide/prompt.md) |
| Understand the full workstation | [Architecture](guide/architecture.md) and [appearance](guide/appearance.md) |
| Adapt this structure to your hardware | [Add a host](guide/add-host.md) |
| Maintain a configuration over time | [Update and recover](guide/update-and-recover.md), [recovery drills](guide/recovery-drills.md), and [validation records](guide/validation.md) |

## Small examples, real configuration

The starter has its own lockfile and a small set of public inputs. It does not
import the personal hosts, enable proprietary applications, or provision secrets.
The recipes then show ordinary Home Manager modules from the actual repository.

The full workstations go further, including shared appearance settings, font
selection, desktop services, and host-managed secrets. Their hardware and runtime
requirements are explicit in the [support table](guide/support.md).

The repository also keeps detailed [operational guides and research](https://github.com/nix-forge/nix-conf/tree/main/docs).
Those notes explain individual decisions and recorded results. You do not need
to read them all before starting.

## Help improve the guide

A failed step is useful feedback. Report the page, source revision, platform,
and smallest redacted reproduction using the
[guide feedback form](https://github.com/nix-forge/nix-conf/issues/new?template=guide-feedback.yml).
See [contributing](guide/contributing.md) for manageable first contributions.
If a recipe helps you, a GitHub star makes the project easier to find again.
