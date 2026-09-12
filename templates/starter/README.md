# A small Home Manager starter

Build Git, Bash aliases, and a colored prompt without changing your account.
This directory is an independent flake. Its only inputs are Nixpkgs and Home
Manager, pinned to matching 26.05 releases in `flake.lock`.

## Build and inspect

Install [Nix](https://nix.dev/install-nix) with the `nix-command` and `flakes`
experimental features enabled. Copy this directory into a new directory outside
the checkout, then run these commands there:

```sh
nix build .#homeConfigurations.x86_64-linux.activationPackage
cat result/home-files/.config/git/config
cat result/home-files/.config/starship.toml
nix build .#checks.x86_64-linux.generated-config
```

Use `aarch64-linux` for ARM Linux or `aarch64-darwin` for Apple silicon.
A successful build creates store files and a `result` link. It does not run the
activation script or change your Git and shell configuration. The generated
configuration check reads the actual output with Git and a TOML parser.

The starter deliberately leaves Git's author identity unset. `git st` will show
short status with branch information, new repositories use `main`, and pulls
only fast-forward. Bash defines `gs` and `ll`; Starship displays the directory,
Git branch, and a colored `>` that works with an ordinary terminal font.

## Adapt your account

Edit `home.nix` to set your login name and home directory. Add your Git identity
there when you are ready to create commits:

```nix
programs.git.settings.user = {
  name = "Your Name";
  email = "YOUR_ID+YOUR_HANDLE@users.noreply.github.com";
};
```

Use the exact address shown in your GitHub email settings, or another public
commit address you choose. Rebuild and inspect the output. Home Manager takes
ownership of the files it manages and refuses conflicting existing files unless
you explicitly arrange backups. Read the
[Home Manager activation guidance](https://nix-community.github.io/home-manager/usage.html)
before applying it to an existing account.

When you have reviewed those changes, activate with the CLI from this flake's
pinned Home Manager input:

```sh
nix run .#home-manager -- switch --flake .#x86_64-linux
```

Keep `home.stateVersion` at your first activation version when updating inputs.
`nix flake update` updates the lockfile; review Home Manager release notes, build,
and inspect again before switching.

## Practice in a VM

On x86 Linux with KVM available, build a disposable NixOS console VM:

```sh
nix build .#vm --out-link result-vm
./result-vm/bin/run-nix-guide-vm
```

The VM logs into the neutral `learner` account and activates the same `home.nix`.
Try `git init practice`, `cd practice`, `git st`, and `alias gs`. The VM has no
SSH service or password-based remote login. Press `Ctrl-a`, then `x` to stop
QEMU. It creates `nix-guide.qcow2` in the working directory; remove that file to
reset the VM's data.

Run the automated boot and activation test with:

```sh
nix build .#checks.x86_64-linux.vm-runtime -L
```

The test verifies the Home Manager service, Git behavior, Bash alias, and prompt
inside the VM. Darwin and ARM targets expose Home Manager builds and generated
configuration checks; the VM is an x86 Linux target.

## Files to change

| File | Owns |
| --- | --- |
| `home.nix` | Account identity, state version, module selection |
| `modules/git.nix` | Git defaults and ignored files |
| `modules/shell.nix` | Bash history and aliases |
| `modules/prompt.nix` | Prompt content and colors |
| `vm.nix` | Disposable NixOS machine and Home Manager integration |
| `flake.nix` | Supported platforms, public inputs, output names |
| `flake.lock` | Exact input revisions |

The complete workstation has more opinionated Git, file search, and prompt
modules. Start with these small files and use the repository's recipes to adopt
additional behavior. The starter does not import the workstation's hardware,
secrets, custom packages, or deployment settings.
