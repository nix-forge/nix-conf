# Try a small graphical VM

This x86 Linux demo boots into Sway and Foot with the repository's reusable Git,
file-search, shell integration, and prompt modules. It uses a small free font
set and software rendering. It contains no workstation hardware configuration,
private state, proprietary application, or secret input.

From the root checkout with initialized submodules, on x86 Linux with KVM:

```sh
nix build .#public-demo-vm --out-link result-demo
demo=$(readlink -f result-demo)
demo_directory=$(mktemp -d)
(cd "$demo_directory" && "$demo/bin/run-nix-public-demo-vm")
```

On the desktop host, run the build through `workstation-task`. The build uses
the root lockfile. Launch QEMU in an empty temporary working directory to keep
the disposable `nix-public-demo.qcow2` disk separate from other files. Closing
QEMU stops the VM; deleting that disk resets its state.

The VM logs into `learner` at the local console and opens a terminal. It does
not run SSH. Type `git init practice`, `cd practice`, and `git st`. The shared
Git module enables rebasing pulls and leaves author identity unset. That differs
from the smaller starter's fast-forward-only policy.

| Keys | Action |
| --- | --- |
| Alt+Enter | Open another Foot terminal |
| Alt+Shift+Q | Close the focused window |
| Alt+1 or Alt+2 | Change workspace |
| Alt+Shift+E | Exit the compositor |

Run its automated test on native x86 Linux:

```sh
nix build --no-link .#checks.x86_64-linux.public-demo-runtime -L
```

The test waits for Home Manager activation and a logged-in Sway session, checks
the compositor's live window tree, presses the terminal keybinding, types a Git
command into the focused terminal, checks the resulting output, and closes the
window with its keybinding. The test captures a disposable VM screenshot.

This demonstrates the reusable home modules in a graphical environment. It does
not test the physical Hyprland/Noctalia desktop, GPU acceleration, HDR, audio,
suspend, screen locking, portals, or hardware security. The example intentionally
has no lock workflow because it is an automatically logged-in disposable VM.
Use the workstation's operational validation for those physical desktop claims.
