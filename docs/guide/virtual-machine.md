# Try a NixOS virtual machine

On an `x86_64-linux` machine with KVM, the starter can boot a small NixOS system
with the same user environment. It uses a serial console, so you do not need a
graphical session or the full desktop packages.

In the copied starter directory:

```sh
nix build .#vm --out-link result-vm
./result-vm/bin/run-nix-guide-vm
```

The console signs in to the disposable `learner` account. This convenient login
belongs only to the VM example. Do not copy it into a real machine installation.

Try `git config --get init.defaultBranch`, `git init /tmp/example`, and `git st`
inside that repository. You should see the configured branch and alias behavior.
Use Ctrl+A followed by X to stop the serial VM. Its disk lives in the directory
where you launch it; retain it to continue experimenting or remove the example's
`.qcow2` disk after shutdown to start fresh. Do not delete unrelated VM images.

## Run the automated exercise

```sh
nix build .#checks.x86_64-linux.vm-runtime -L
```

The test boots the example, waits for Home Manager activation, and exercises the
configured Git and shell behavior. It uses disposable test disks. Evaluation,
generated-file checks, and this runtime test each cover a different part of the
configuration.

The test requires KVM access. A permission failure involving `/dev/kvm` is a host
setup problem, not proof of a broken Nix module. See the
[NixOS VM tutorial](https://nix.dev/tutorials/nixos/nixos-configuration-on-vm.html).
A VM does not establish physical GPU, HDR, Bluetooth, or suspend compatibility.
