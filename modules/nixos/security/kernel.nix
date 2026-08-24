{ config, lib, ... }:
let
  cfg = config.security.kernelBaseline;
  unsafeMitigationParameters = [
    "mitigations=off"
    "noibrs"
    "noibpb"
    "nospectre_v1"
    "nospectre_v2"
    "nospec_store_bypass_disable"
    "l1tf=off"
    "mds=off"
    "no_stf_barrier"
  ];
in
{
  options.security.kernelBaseline.enable = lib.mkEnableOption ''
    the production desktop kernel-hardening baseline
  '';

  config = lib.mkIf cfg.enable {
    # NixOS implements this as `nohibernate` and the one-way
    # kernel.kexec_load_disabled sysctl. It preserves ordinary reboot and boot
    # generation rollback while preventing in-place replacement of the kernel.
    security.protectKernelImage = true;

    boot.kernelParams = [
      # The current upstream x86_64 kernel defaults this to enabled, but make
      # the memory-corruption mitigation explicit for every boot generation.
      "randomize_kstack_offset=on"

      # These reduce useful kernel heap-layout predictability. They have a
      # modest memory cost, but avoid the severe latency and allocation costs
      # of debugging-only options such as page poisoning or slub_debug.
      "slab_nomerge"
      "page_alloc.shuffle=1"

      # debugfs is a diagnostic interface, not a normal desktop requirement.
      # Disabling it removes a broad collection of kernel-specific knobs and
      # information leaks without affecting sysfs, procfs, or BPF filesystems.
      "debugfs=off"
    ];

    boot.kernel.sysctl = {
      # Keep privileged kernel information and diagnostics out of ordinary
      # user sessions. Administrators retain deliberate access through root.
      "kernel.kptr_restrict" = 2;
      "kernel.dmesg_restrict" = 1;
      "kernel.perf_event_paranoid" = 3;
      "kernel.sysrq" = 0;

      # Block unprivileged BPF permanently for a running boot. Privileged BPF
      # users such as systemd retain the required capabilities. This is a
      # deliberate security boundary rather than disabling the BPF JIT, whose
      # loss would penalize legitimate privileged networking and observability.
      "kernel.unprivileged_bpf_disabled" = 1;

      # Prevent automatic loading of a tty line discipline from an ioctl.
      # Standard terminal operation uses the built-in N_TTY discipline.
      "dev.tty.ldisc_autoload" = 0;

      # Harden common world-writable-directory race and privileged-coredump
      # paths. Level 2 extends the FIFO/regular-file protections to group-
      # writable sticky directories.
      "fs.suid_dumpable" = 0;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "fs.protected_symlinks" = 1;
      "fs.protected_hardlinks" = 1;

      # Keep the strongest practical ASLR values for 64-bit desktop programs.
      "kernel.randomize_va_space" = 2;
      "vm.mmap_rnd_bits" = 32;
      "vm.mmap_min_addr" = 65536;
    };

    assertions = [
      {
        assertion = config.security.protectKernelImage;
        message = "security.kernelBaseline requires security.protectKernelImage so hibernation and in-place kexec replacement remain disabled.";
      }
      {
        assertion = lib.all (
          parameter: !lib.elem parameter config.boot.kernelParams
        ) unsafeMitigationParameters;
        message = "security.kernelBaseline rejects kernel parameters that disable CPU vulnerability mitigations. Keep the kernel defaults, or disable this baseline only for a deliberately isolated benchmark system.";
      }
      {
        # SELinux and AppArmor are competing major MAC choices. NixOS has a
        # supported AppArmor path, whereas complete SELinux policy/labelling
        # integration is not currently a production-ready NixOS baseline.
        assertion = lib.elem "apparmor" config.security.lsm && !lib.elem "selinux" config.security.lsm;
        message = "security.kernelBaseline requires the supported AppArmor LSM path and does not support adding SELinux alongside it.";
      }
      {
        assertion = lib.elem "debugfs=off" config.boot.kernelParams;
        message = "security.kernelBaseline requires debugfs=off.";
      }
      {
        assertion = config.boot.kernel.sysctl."kernel.unprivileged_bpf_disabled" == 1;
        message = "security.kernelBaseline requires kernel.unprivileged_bpf_disabled = 1; changing it requires a reboot because this value is one-way.";
      }
    ];

    # Do not set `mitigations=off`, speculative-execution opt-outs, PTI, SMT,
    # `module.sig_enforce=1`, lockdown, `modules_disabled`, or a broad driver/
    # filesystem blacklist here. Those are hardware-, workload-, and boot-chain
    # dependent. In particular, forced module signing or lockdown is unsafe
    # before a complete Secure Boot key-enrollment and signed out-of-tree
    # module design exists. The host-local file makes the desktop's performance
    # choices and unused protocol modules explicit.
  };
}
