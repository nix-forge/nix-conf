# Support and validation

The personal workstation and public examples have different support boundaries.
A platform declared in a flake is not evidence that every feature has run there.

| Target | Evaluation | Native build | Runtime evidence |
| --- | --- | --- | --- |
| Starter, `x86_64-linux` | Public lock and current integration checks | Activation package and small VM | Automated VM boots and exercises Home Manager, Git, Bash, and Starship |
| Starter, `aarch64-linux` | All-system evaluation | Configured for native CI | No local runtime claim |
| Starter, `aarch64-darwin` | All-system evaluation | Configured for native CI | No local macOS activation claim |
| Graphical demo, `x86_64-linux` | Root lock and demo configuration | Native QEMU test | Sway session, Foot configuration, terminal keybindings and typed Git command |
| Darwin example, `aarch64-darwin` | Independent stable lock and assertions | System closure and generated configuration check | Generated launchd command exercised; no activation claim |
| Personal desktop | Existing host checks | Full closure belongs on the desktop host | Feature-specific results in operational notes |
| Personal Mac | Existing host checks | Requires a suitable Apple Silicon Mac | Feature-specific native checks; Linux does not establish macOS behavior |

Intel macOS is outside the declared public platform set. The serial VM example is
x86 Linux only. It does not test physical graphics, suspend, audio devices, or
hardware security.

## What the checks establish

From the nix-conf checkout:

```sh
nix build .#documentation
nix build .#checks.x86_64-linux.public-guide-recipes
bash tests/public-guide/check-consumers.sh
```

On the desktop host, run these commands through `workstation-task`.

The documentation build checks links, generated option references and embedded
example consistency. The recipe check imports the documented Git, file-search
and prompt modules using the root's pinned inputs. The separate consumer script
extracts both exported templates and tests actual source and typed module inputs;
see [public example checks](public-examples.md) for their scope.

Inside the copied starter, run its `generated-config` check on your system and
its `vm-runtime` check on x86 Linux. Those use the starter's own lockfile.
Separating the two catches both public-example failures and changes in the
current workstation dependencies.

CI is configured to build these checks on their supported runners. A new workflow
or working-tree change has not passed hosted CI until its actual run succeeds.
Use the [Actions history](https://github.com/nix-forge/nix-conf/actions) and record
the source revision with any claim about a result.

## Reporting a problem

Use the [bug form](https://github.com/nix-forge/nix-conf/issues/new?template=bug.yml)
or [guide feedback form](https://github.com/nix-forge/nix-conf/issues/new?template=guide-feedback.yml).
The project maintains a focused workstation and learning guide; it cannot promise
support for every hardware combination or every upstream release.
